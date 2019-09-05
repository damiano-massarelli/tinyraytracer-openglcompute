#include <iostream>
#include <SDL.h>
#include <glad/glad.h>
#include <stdint.h>
#include <cmath>
#include "Shader.h"
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>
#include <glm/glm.hpp>
#include "debug.h"
#include "FreeCam.h"

// use nvidia gpu if available
extern "C" {
	_declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
}


SDL_Window* initScreen(int width, int height) {
	if (SDL_Init(SDL_INIT_VIDEO) < 0) {
		std::cout << "cannot init sdl " << SDL_GetError() << "\n";
		return nullptr;
	}

	SDL_GL_LoadLibrary(nullptr); // use default OpenGL
	SDL_GL_SetAttribute(SDL_GL_ACCELERATED_VISUAL, 1);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

	SDL_Window* window = SDL_CreateWindow("tinyraytracer-openglcompute", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height, SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL);
	if (window == nullptr) {
		std::cout << "cannot create window " << SDL_GetError() << "\n";
		return nullptr;
	}

	SDL_GL_CreateContext(window);

	// Use v-sync
	SDL_GL_SetSwapInterval(1);

	if (!gladLoadGLLoader(SDL_GL_GetProcAddress)) {
		std::cout << "Failed to initialize GLAD\n";
		return nullptr;
	}

	glEnable(GL_DEBUG_OUTPUT);
	glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
	glDebugMessageCallback(glDebugOutput, nullptr);
	glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, 0, nullptr, GL_TRUE);

	glViewport(0, 0, width, height);

	return window;
}

GLuint createTexture(int w, int h) {
	GLuint texture;
	glGenTextures(1, &texture);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, texture);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, w, h, 0, GL_RGBA, GL_FLOAT, nullptr);

	glBindTexture(GL_TEXTURE_2D, 0);

	return texture;
}

GLuint createCubeMap() {
	stbi_set_flip_vertically_on_load(false);

	GLuint cubemap;
	glGenTextures(1, &cubemap);

	glBindTexture(GL_TEXTURE_CUBE_MAP, cubemap);
	int width, height, numCh;
	std::vector<std::string> images{ "right", "left", "top", "bottom", "back", "front" };
	int i = 0;
	for (const auto& img : images) {
		std::uint8_t* data = stbi_load(("../data/" + img + ".tga").c_str(), &width, &height, &numCh, STBI_rgb_alpha);
		if (data) {
			glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
			stbi_image_free(data);
		}
		else
			std::cout << "unable to load texture " << img << "\n";

		i++;
	}
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

	glBindTexture(GL_TEXTURE_CUBE_MAP, 0);

	return cubemap;
}

constexpr GLuint width = 1024;
constexpr GLuint height = 768;

constexpr GLuint groupSize = 16;

int main(int argc, char* argv[])
{
	SDL_Window* window = initScreen(width, height);

	int workGroupCount[3] = { 0 };
	glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 0, &workGroupCount[0]);
	glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 1, &workGroupCount[1]);
	glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 2, &workGroupCount[2]);
	int maxInvocations;

	glGetIntegerv(GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS, &maxInvocations);

	std::cout << "max ivoc " << maxInvocations << "\n";
	std::cout << "max count " << workGroupCount[0] << " " << workGroupCount[1] << " " << workGroupCount[2] << "\n";

	FreeCam cam{ glm::vec3{ 0.0 } };

	float vertices[]{ -1.0f, 1.0f,
					  -1.0f, -1.0f,
					   1.0f, 1.0f,
					   1.0f, -1.0f };

	std::uint32_t VAO;
	glGenVertexArrays(1, &VAO);

	std::uint32_t VBO;
	glGenBuffers(1, &VBO);

	glBindVertexArray(VAO);

	glBindBuffer(GL_ARRAY_BUFFER, VBO);
	glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), (void *)0);
	glEnableVertexAttribArray(0);

	glBindVertexArray(0);
	glBindBuffer(GL_ARRAY_BUFFER, 0);

	Shader drawShader{ "shaders/renderTexVS.glsl", "shaders/renderTexFS.glsl" };

	Shader renderShader{ {{GL_COMPUTE_SHADER, "shaders/compute.glsl"}} };


	GLuint outputTexture = createTexture(width, height);
	GLuint skybox = createCubeMap();

	bool quit = false;
	SDL_Event e;

	while (!quit) {
		while (SDL_PollEvent(&e) != 0) {
			if (e.type == SDL_QUIT) quit = true;
		}

		cam.update();

		renderShader.use();
		renderShader.setVec3("cameraPosition", cam.position);
		renderShader.setMat3("cameraOrientation", cam.getLookAt());
		glActiveTexture(GL_TEXTURE0);
		glBindImageTexture(0, outputTexture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);

		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_CUBE_MAP, skybox);

		glDispatchCompute(width / groupSize, height / groupSize, 1);

		glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
		
		// no need to clear we are rendering a full screen texture

		drawShader.use();
		glBindVertexArray(VAO);
		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_2D, outputTexture);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

		SDL_GL_SwapWindow(window);
	}

	SDL_DestroyWindow(window);
	SDL_Quit();

	return 0;
}