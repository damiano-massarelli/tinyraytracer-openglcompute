#ifndef SHADER_H
#define SHADER_H
#include <string>
#include <glad/glad.h>
#include <stdint.h>
#include <glm/glm.hpp>
#include <vector>
#include <utility>

class Shader
{
    private:
        std::uint32_t programId = 0;

        std::uint32_t createShader(const std::string& path, GLenum type);

		void createProgram(const std::vector<std::pair<GLenum, std::string>>& shaders);

    public:
        Shader(const std::string& vertexPath, const std::string& fragmentPath, const std::string& geometryPath = "");

		Shader(const std::vector<std::pair<GLenum, std::string>>& shaders);

        Shader(const Shader& shader) = delete;

        Shader& operator=(const Shader& shader) = delete;

        std::int32_t getLocationOf(const std::string& name, bool warning = true) const;

        void setFloat(const std::string& name, float value) const;

        void setInt(const std::string& name, int value) const;

        void setMat4(const std::string& name, const glm::mat4& value) const;

		void setMat3(const std::string& name, const glm::mat3& value) const;

        void setVec3(const std::string& name, const glm::vec3& value);

        void use() const;

        virtual ~Shader();
};

#endif // SHADER_H
