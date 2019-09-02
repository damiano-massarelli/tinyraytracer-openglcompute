#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D outTexture;

// UNIFORMS

uniform vec3 cameraPosition;
uniform mat3 cameraOrientation;

layout (binding = 1) uniform samplerCube skybox;

// CONTS

const float FOV = 3.14 / 2;

const int MAX_DEPTH = 4;

// DATA DEFINITIONS

/* Stack data structure */
struct Stack {
	int data[15]; // -1: a tree of depth N has 2^N - 1 elements
	int head;
};

/* Simple material */
struct Material {
	vec3 color;
	float reflectivity;
	float refractivity;
	float specularExponent;
	float refractiveRatio;
};

/* Emulates a stack record */
struct FunData {
	// params
	int index;
	vec3 orig;
	vec3 dir;
	int depth;

	// local vars
	Material mat;
	bool finished;

	// return data
	vec3 retColor;
};

struct Sphere {
	vec3 center;
	float radius;
	Material mat;
};

struct Plane {
	vec3 center;
	vec3 normal;
	float size;
	Material mat;
};

struct Light {
	vec3 position;
	vec3 color;
};

const int SPHERE_COUNT = 4;
Sphere spheres[SPHERE_COUNT];

const int PLANE_COUNT = 1;
Plane planes[PLANE_COUNT];

const int LIGHT_COUNT = 3;
Light lights[LIGHT_COUNT];

// FUNCTION DEFINITIONS

// stack funcitons

Stack createStack() {
	Stack s;
	s.head = -1;
	return s;
}

int pop(inout Stack s) {
	s.head -= 1;
	return s.data[s.head + 1];
}

void push(inout Stack s, int val) {
	s.head += 1;
	s.data[s.head] = val;
}

int top(Stack s) {
	return s.data[s.head];
}

bool empty(Stack s) {
	return s.head < 0;
}

// -----

// hit testing

bool hitSphere(Sphere sphere, vec3 orig, vec3 dir, out vec3 normal, out vec3 hitpoint, out Material mat) {
	vec3 e = sphere.center - orig;

	float eDotDir = dot(e, dir);

	float b = sphere.radius * sphere.radius - dot(e, e) + pow(eDotDir, 2);

	if (b >= 0) {
		float t = eDotDir - sqrt(b);

		if (t < 0) return false;

		hitpoint = orig + t * dir;
		normal = normalize(hitpoint - sphere.center);

		mat = sphere.mat;

		return true;
	}

	return false;
}

bool hitPlane(Plane plane, vec3 orig, vec3 dir, out vec3 normal, out vec3 hitpoint, out Material mat) {
	float d = dot(plane.center, plane.normal);

	float dirDotN = dot(dir, plane.normal);

	if (abs(dirDotN) < 0.001) return false;

	float t = (d - dot(orig, plane.normal)) / dirDotN;

	if (t < 0) return false;

	hitpoint = orig + t * dir;
	vec3 size = abs(hitpoint - plane.center);

	vec2 size2;
	if (size.x < 0.01) size2 = size.yz;
	if (size.y < 0.01) size2 = size.xz;
	if (size.z < 0.01) size2 = size.xy;

	if (any(greaterThan(size2, vec2(plane.size)))) return false;

	normal = plane.normal;
	mat = plane.mat;

	return true;
}

bool sceneIntersect(vec3 orig, vec3 dir, out vec3 normal, out vec3 hitpoint, out Material mat) {
	vec3 outNormal;
	vec3 outHit;
	Material outMat;

	float dist = 1e10;
	bool found = false;

	float hitdist = 0.0;

	for (int i = 0; i < SPHERE_COUNT; i++) {
		if (hitSphere(spheres[i], orig, dir, outNormal, outHit, outMat)) {
			found = true;

			// depth testing plz
			hitdist = distance(orig, outHit);
			if (hitdist < dist) {
				dist = hitdist;
				normal = outNormal;
				hitpoint = outHit;
				mat = outMat;
			}
		}
	}

	for (int i = 0; i < PLANE_COUNT; i++) {
		if (hitPlane(planes[i], orig, dir, outNormal, outHit, outMat)) {
			found = true;

			// depth testing plz
			hitdist = distance(orig, outHit);
			if (hitdist < dist) {
				dist = hitdist;
				normal = outNormal;
				hitpoint = outHit;
				mat = outMat;
			}
		}
	}

	return found;
}

/* Cast a ray and if something is hit calculates and returns its color according to the lights in the scene */
bool castRay(vec3 orig, vec3 dir, out vec3 outColor, out vec3 hitpoint, out vec3 normal, out Material mat) {

	outColor = vec3(0.0);

	if (!sceneIntersect(orig, dir, normal, hitpoint, mat)) {
		outColor = texture(skybox, dir).rgb;
		return false;
	}

	for (int i = 0; i < LIGHT_COUNT; i++) {
		Light light = lights[i];

		// diffuse component
		vec3 rayToLight = normalize(light.position - hitpoint);
		outColor += mat.color * light.color * max(0.0, dot(normal, rayToLight));

		// specular component
		vec3 rayToCamera = normalize(orig - hitpoint);
		float specularFactor = max(0.0, dot(rayToCamera, -reflect(rayToLight, normal)));
		outColor += light.color * pow(specularFactor, mat.specularExponent);

		// shadows if something is hit in the path from the hitpoint to the light then this point is in shadow
		vec3 shadowOrigin = hitpoint + normal * 1e-3 * sign(dot(rayToLight, normal));
		vec3 hitpt, norm;
		Material m;
		bool hit = sceneIntersect(shadowOrigin, rayToLight, norm, hitpt, m);
		if (hit)
			outColor *= 0.8;
	}
	
	return true;
}

/* Emulates a recursive function. For each ray that is cast
* two more rays (reflected and refracted) are generated. This
* creates a tree-like data structure in which the color generated
* by the first ray depends on the colors of the children rays.
* This tree can be flattened as in max/min heap data structures. 
* the flattened tree can then be explored with an iterative algorithm. */
vec3 recursiveRayCast(vec3 orig, vec3 dir) {

	Stack s = createStack();
	FunData data[16];

	Material _emptyMaterial = Material(vec3(0.0), 0.0, 0.0, 0.0, 0.0);

	push(s, 1);
	data[1] = FunData(1, orig, dir, 0, _emptyMaterial, false, vec3(0.0));

	while (!empty(s)) {
		const int i = top(s);

		if (data[i].finished) {
			if (data[i].depth != MAX_DEPTH - 1)
				data[i].retColor += data[2 * i].retColor * data[i].mat.reflectivity + data[2 * i + 1].retColor * data[i].mat.refractivity;
			
			// else: the return value is already there

			pop(s);
			continue;
		}

		// did not hit continue so its is the first time we get here!
		vec3 hitpoint;
		vec3 normal;
		Material mat;
		vec3 col;

		bool hit = castRay(data[i].orig, data[i].dir, data[i].retColor, hitpoint, normal, mat);
		data[i].finished = true;

		// nothing was hit, return value is already in place, no need to trace more rays!
		if (!hit) {
			pop(s);
			continue;
		}

		data[i].mat = mat;

		if (data[i].depth != MAX_DEPTH - 1) {
			vec3 reflected = normalize(reflect(data[i].dir, normal));
			vec3 refracted = normalize(refract(data[i].dir, normal, data[i].mat.refractiveRatio));

			vec3 reflectedOrigin = hitpoint + normal * 1e-3 * sign(dot(reflected, normal));
			vec3 refractedOrigin = hitpoint + normal * 1e-3 * sign(dot(refracted, normal));

			data[2 * i] = FunData(2 * i, reflectedOrigin, reflected, data[i].depth + 1, _emptyMaterial, false, vec3(0.0));
			data[2 * i + 1] = FunData(2 * i + 1, refractedOrigin, -refracted, data[i].depth + 1, _emptyMaterial, false, vec3(0.0));
			push(s, 2 * i);
			push(s, 2 * i + 1);
		}
	}

	return data[1].retColor;
}

// -------

void main() {
	// Scene set-up

	Material ivory = Material(vec3(255, 255, 240) / 255., 0.1, 0.0, 50.0, 1.0);

	Sphere s1;
	s1.center = vec3(-3, 0, -16);
	s1.radius = 2;
	s1.mat = ivory;
	spheres[0] = s1;

	Material glass = Material(vec3(0.3, 0.3, 0.3), 0.1, 0.8, 125, 1.0 / 1.5);
	Sphere s2;
	s2.center = vec3(-1.0, -1.5, -12);
	s2.radius = 2;
	s2.mat = glass;
	spheres[1] = s2;

	Material redRubber = Material(vec3(0.9, 0.1, 0.0), 0.0, 0.0, 10, 1.0);
	Sphere s3;
	s3.center = vec3(1.5, -0.5, -18);
	s3.radius = 2;
	s3.mat = redRubber;
	spheres[2] = s3;

	Material mirror = Material(vec3(0.0), 0.95, 0.0, 1425., 1.0);
	Sphere s4;
	s4.center = vec3(7, 5, -18);
	s4.radius = 2;
	s4.mat = mirror;
	spheres[3] = s4;

	Material groundMat = Material(vec3(248, 131, 121) / 255., 0.05, 0.03, 8., 0.9);
	Plane ground = Plane(vec3(0, -4, -15), vec3(0, 1, 0), 15, groundMat);
	planes[0] = ground;

	Light l1;
	l1.color = vec3(1.5);
	l1.position = vec3(-20, 20, 20);
	lights[0] = l1;

	Light l2;
	l2.color = vec3(1.8);
	l2.position = vec3(30, 50, -25);
	lights[1] = l2;

	Light l3;
	l3.color = vec3(1.7);
	l3.position = vec3(30, 20, 30);
	lights[2] = l3;

	// ray casting

    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texSize = imageSize(outTexture);

    // ray origin
    vec3 p = cameraPosition;

    // ray direction
	vec3 d = vec3(0.0, 0.0, -1.0);
	d.xy = 2.0 * (-0.5 + vec2(pixelCoords) / texSize) * tan(FOV / 2.0);
	d = cameraOrientation * normalize(d);

	vec4 pixelColor = vec4(0.0, 0.0, 0.0, 1.0);

	pixelColor.rgb = recursiveRayCast(p, d);

	// tone mapping
	pixelColor.rgb = vec3(1.0) - exp(-pixelColor.rgb);

    imageStore(outTexture, pixelCoords, pixelColor);
}