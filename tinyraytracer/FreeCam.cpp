#include "FreeCam.h"
#include <SDL.h>

FreeCam::FreeCam(const glm::vec3& pos) : position{pos}
{

}

void FreeCam::update()
{
    float cameraSpeed = 0.5f;
    glm::vec3 cameraFront = getCameraDirection();
    const Uint8* state = SDL_GetKeyboardState(nullptr);
    if (state[SDL_SCANCODE_W])
        position += cameraFront * cameraSpeed;
    if (state[SDL_SCANCODE_S])
        position -= cameraFront * cameraSpeed;
    if (state[SDL_SCANCODE_D])
        position -= glm::cross(glm::vec3{0.0f, 1.0f, 0.0f}, cameraFront) * cameraSpeed;
    if (state[SDL_SCANCODE_A])
        position += glm::cross(glm::vec3{0.0f, 1.0f, 0.0f}, cameraFront) * cameraSpeed;

    int xpos, ypos;
    SDL_GetMouseState(&xpos, &ypos);
    if (firstMouse) {
        lastMouseX = xpos;
        lastMouseY = ypos;
        firstMouse = false;
    }
    double xoff = xpos - lastMouseX;
    double yoff = ypos - lastMouseY;
    lastMouseX = xpos;
    lastMouseY = ypos;

    heading -= xoff * sensitivity;
    pitch -= yoff * sensitivity;
}

glm::vec3 FreeCam::getCameraDirection() const
{
    glm::quat rotation{glm::vec3{pitch, heading, 0.0f}};
    return glm::toMat3(rotation) * glm::vec3{0.0f, 0.0f, -1.0f};
    // -1 on the z: by default when no camera is used (heading = pitch = 0)
    // opengl looks towards negative values of z
}

glm::vec3 FreeCam::getCameraUp() const
{
    glm::quat rotation{glm::vec3{pitch, heading, 0.0f}};
    return glm::toMat3(rotation) * glm::vec3{0.0f, 1.0f, 0.0f};
}

glm::mat3 FreeCam::getLookAt() const
{
    glm::quat rotation{glm::vec3{pitch, heading, 0.0f}};
    glm::mat4 view = glm::toMat4(rotation);
	return view;
}

FreeCam::~FreeCam()
{

}
