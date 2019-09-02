#version 430
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba32f, binding = 0) uniform image2D outTexture;

// UNIFORMS

uniform vec3 cameraPosition;
uniform mat3 cameraOrientation;

// CONTS

const float FOV = 3.14 / 2;

const int MAX_DEPTH = 4;

// DATA DEFINITIONS

struct Stack {
	int data[15]; // -1: a tree of depth N has 2^N - 1 elements
	int head;
};

struct Material {
	vec3 color;
	float reflectivity;
	float refractivity;
	float specularExponent;
};

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

const int SPHERE_COUNT = 2;
Sphere spheres[SPHERE_COUNT];

const int PLANE_COUNT = 1;
Plane planes[PLANE_COUNT];

const int LIGHT_COUNT = 2;
Light lights[LIGHT_COUNT];

// FUNCTION DEFINITIONS

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

	if (any(greaterThan(size2, vec2(5.0)))) return false;

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

bool castRay(vec3 orig, vec3 dir, out vec3 outColor, out vec3 hitpoint, out vec3 normal, out Material mat) {

	outColor = vec3(0.0);

	if (!sceneIntersect(orig, dir, normal, hitpoint, mat)) {
		outColor = vec3(0.0, 0.34, 0.72);
		return false;
	}

	for (int i = 0; i < LIGHT_COUNT; i++) {
		Light light = lights[i];

		vec3 rayToLight = normalize(light.position - hitpoint);

		outColor += mat.color * light.color * max(0.0, dot(normal, rayToLight));

		vec3 rayToCamera = normalize(orig - hitpoint);
		float specularFactor = max(0.0, dot(rayToCamera, -reflect(rayToLight, normal)));


		outColor += light.color * pow(specularFactor, mat.specularExponent);
	}
	
	return true;
}

vec3 recursiveRayCast(vec3 orig, vec3 dir) {

	Stack s = createStack();
	FunData data[16];

	Material _emptyMaterial = Material(vec3(0.0), 0.0, 0.0, 0.0);

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

		bool res = castRay(data[i].orig, data[i].dir, data[i].retColor, hitpoint, normal, mat);
		data[i].finished = true;

		// nothing was hit, return value is already in place, no need to trace more rays!
		if (!res) {
			pop(s);
			continue;
		}

		data[i].mat = mat;

		if (data[i].depth != MAX_DEPTH - 1) {
			vec3 reflected = normalize(reflect(data[i].dir, normal));
			vec3 refracted = normalize(refract(data[i].dir, normal, 1.0 / 1.52));

			vec3 reflectedOrigin = hitpoint + normal * 1e-3 * dot(reflected, normal);
			vec3 refractedOrigin = hitpoint + normal * 1e-3 * dot(refracted, normal);

			data[2 * i] = FunData(2 * i, reflectedOrigin, reflected, data[i].depth + 1, _emptyMaterial, false, vec3(0.0));
			data[2 * i + 1] = FunData(2 * i + 1, refractedOrigin, refracted, data[i].depth + 1, _emptyMaterial, false, vec3(0.0));
			push(s, 2 * i);
			push(s, 2 * i + 1);
		}
	}

	return data[1].retColor;
}



void main() {
	Material green = Material(vec3(0, 1, 0), 0.4, 0.7, 16);

	Sphere s1;
	s1.center = vec3(1, 1, -10);
	s1.radius = 2;
	s1.mat = green;
	spheres[0] = s1;

	Material red = Material(vec3(0, 0, 0), 0.5, 0.0, 1);
	Sphere s2;
	s2.center = vec3(0, 2, -5);
	s2.radius = 1;
	s2.mat = red;
	spheres[1] = s2;

	Material glass = Material(vec3(0.9), 0.0, 0.0, 12);
	Plane ground = Plane(vec3(0, -3, -5), vec3(0, 1, 0), 10, glass);
	planes[0] = ground;

	Light l1;
	l1.color = vec3(1.0);
	l1.position = vec3(0.0);
	lights[0] = l1;

	Light l2;
	l2.color = vec3(1.0);
	l2.position = vec3(-5, 0, -2);
	lights[1] = l2;


	Stack s = createStack();
	push(s, 3);
	push(s, 1);

	int a = pop(s);

    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy); // [0, 0] -> [511, 511]
    ivec2 texSize = imageSize(outTexture);

    // ray origin
    vec3 p = cameraPosition;

    // ray direction
	vec3 d = vec3(0.0, 0.0, -1.0);
	d.xy = 2.0 * (-0.5 + vec2(pixelCoords) / texSize) * tan(FOV / 2.0);
	d = cameraOrientation * normalize(d);

	vec4 pixelColor = vec4(0.0, 0.0, 0.0, 1.0);

	vec3 pt, norm;
	Material mat;

	//castRay(p, d, pixelColor.rgb, pt, norm, mat);

	pixelColor.rgb = recursiveRayCast(p, d);

	// tone mapping
	pixelColor.rgb = vec3(1.0) - exp(-pixelColor.rgb);

    imageStore(outTexture, a * pixelCoords, pixelColor);
}