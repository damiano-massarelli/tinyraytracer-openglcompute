#include "Shader.h"
#include <fstream>
#include <sstream>
#include <iostream>
#include <glm/gtc/type_ptr.hpp>

Shader::Shader(const std::string& vertexPath, const std::string& fragmentPath, const std::string& geometryPath)
{
	std::vector<std::pair<GLenum, std::string>> shaders{
		{GL_VERTEX_SHADER, vertexPath},
		{GL_FRAGMENT_SHADER, fragmentPath}
	};

	if (geometryPath != "")
		shaders.push_back({ GL_GEOMETRY_SHADER, geometryPath });

	createProgram(shaders);
}

Shader::Shader(const std::vector<std::pair<GLenum, std::string>>& shaders)
{
	createProgram(shaders);
}

void Shader::createProgram(const std::vector<std::pair<GLenum, std::string>>& shaders)
{
	std::vector<std::uint32_t> shad;

	for (const auto&[type, path] : shaders)
		shad.push_back(createShader(path, type));

	programId = glCreateProgram();
	for (auto s : shad)
		glAttachShader(programId, s);

	glLinkProgram(programId);

	int success;
	char infoLog[512];
	glGetProgramiv(programId, GL_LINK_STATUS, &success);
	if (!success) {
		glGetProgramInfoLog(programId, 512, nullptr, infoLog);
		programId = 0;
		std::cerr << "linking problem " << infoLog << "\n";
	}

	for (auto s : shad)
		glDeleteShader(s);
}

std::uint32_t Shader::createShader(const std::string& path, GLenum type)
{
    std::ifstream inputSource;
    inputSource.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    std::string source;
    try {
        inputSource.open(path);
        std::stringstream buffer;
        buffer << inputSource.rdbuf();

        source = buffer.str();
    } catch (std::ifstream::failure e) {
        std::cerr << "cannot open " << path << ": " << e.what() << "\n";
        return 0;
    }

    std::uint32_t shader = glCreateShader(type);
    const char* sourceCode = source.c_str();
    glShaderSource(shader, 1, &sourceCode, nullptr);
    glCompileShader(shader);

    int success;
    char infoLog[512];
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        glGetShaderInfoLog(shader, 512, nullptr, infoLog);
        std::cerr << "shader compilation error for " << path << ": " << infoLog << "\n";
        return 0;
    }

    return shader;
}

std::int32_t Shader::getLocationOf(const std::string& name, bool warning) const
{
    std::int32_t location = glGetUniformLocation(programId, name.c_str());
    if (warning && location == -1)
        std::cerr << "unable to find uniform variable " << name << " make sure you are using it in your code\n";
    return location;
}

void Shader::setFloat(const std::string& name, float value) const
{
    std::int32_t location = getLocationOf(name);
    if (location != -1)
        glUniform1f(location, value);
}

void Shader::setInt(const std::string& name, int value) const
{
    std::int32_t location = getLocationOf(name);
    if (location != -1)
        glUniform1i(location, value);
}

void Shader::setMat4(const std::string& name, const glm::mat4& value) const
{
    std::int32_t location = getLocationOf(name);
    if (location != -1)
        glUniformMatrix4fv(location, 1, GL_FALSE, glm::value_ptr(value));
}

void Shader::setMat3(const std::string& name, const glm::mat3& value) const
{
	std::int32_t location = getLocationOf(name);
	if (location != -1)
		glUniformMatrix3fv(location, 1, GL_FALSE, glm::value_ptr(value));
}

void Shader::setVec3(const std::string& name, const glm::vec3& value)
{
    std::int32_t location = getLocationOf(name);
    if (location != -1)
        glUniform3fv(location, 1, glm::value_ptr(value));
}

void Shader::use() const
{
    glUseProgram(programId);
}

Shader::~Shader()
{
    glDeleteProgram(programId);
}


