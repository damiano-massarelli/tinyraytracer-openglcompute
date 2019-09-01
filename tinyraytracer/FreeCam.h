#ifndef FREECAM_H
#define FREECAM_H
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include<glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>

class FreeCam
{
    private:
         double lastMouseX = 0.0;
         double lastMouseY = 0.0;
         bool firstMouse = true;

    public:
        float sensitivity = 0.005f;
        glm::vec3 position{0.0f};
        glm::quat rotation{0.0f, 0.0f, 0.0f, 1.0f};

        float heading = 0.0f;
        float pitch = 0.0f;

        FreeCam(const glm::vec3& pos);

        void update();

        glm::vec3 getCameraDirection() const;

        glm::vec3 getCameraUp() const;

        glm::mat3 getLookAt() const;

        virtual ~FreeCam();
};


#endif // FREECAM_H
