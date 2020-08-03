precision highp float;
precision highp int;
precision highp sampler2D;

uniform mat4 uGLTF_Model_InvMatrix;
uniform mat3 uGLTF_Model_NormalMatrix;
uniform vec3 uGLTF_Model_Position;

#include <pathtracing_uniforms_and_defines>

uniform sampler2D tTriangleTexture;
uniform sampler2D tAABBTexture;

uniform sampler2D tAlbedoMap;
uniform sampler2D tEmissiveMap;
uniform sampler2D tMetallicRoughnessMap;
uniform sampler2D tNormalMap;

//float InvTextureWidth = 0.000244140625; // (1 / 4096 texture width)
//float InvTextureWidth = 0.00048828125;  // (1 / 2048 texture width)
//float InvTextureWidth = 0.0009765625;   // (1 / 1024 texture width)

#define INV_TEXTURE_WIDTH 0.00048828125

#define N_DISKS 1
#define N_SPHERES 3
#define N_BOXES 2
#define N_OPENCYLINDERS 1

//-----------------------------------------------------------------------

struct Ray { vec3 origin; vec3 direction; };
struct Disk { float radius; vec3 pos; vec3 normal; vec3 emission; vec3 color; int type; bool isDynamic; };
struct Sphere { float radius; vec3 position; vec3 emission; vec3 color; int type; bool isDynamic; };
struct OpenCylinder { vec3 pos0; vec3 pos1; float radius; vec3 emission; vec3 color; int type; bool isDynamic; };
struct Box { vec3 minCorner; vec3 maxCorner; vec3 emission; vec3 color; int type; bool isDynamic; };
struct Intersection { vec3 normal; vec3 emission; vec3 color; vec2 uv; int type; int textureID; bool isDynamic; };

Disk disks[N_DISKS];
Sphere spheres[N_SPHERES];
OpenCylinder openCylinders[N_OPENCYLINDERS];
Box boxes[N_BOXES];


#include <pathtracing_random_functions>

#include <pathtracing_calc_fresnel_reflectance>

#include <pathtracing_disk_intersect>

#include <pathtracing_sphere_intersect>
                                
#include <pathtracing_opencylinder_intersect>

#include <pathtracing_box_intersect>

#include <pathtracing_boundingbox_intersect>

#include <pathtracing_bvhTriangle_intersect>

#include <pathtracing_sample_sphere_light>


vec2 stackLevels[24];

struct BoxNode
{
	vec4 data0; // corresponds to .x: idLeftChild, .y: aabbMin.x, .z: aabbMin.y, .w: aabbMin.z
	vec4 data1; // corresponds to .x: idRightChild .y: aabbMax.x, .z: aabbMax.y, .w: aabbMax.z
};

BoxNode GetBoxNode(const in float i)
{
	// each bounding box's data is encoded in 2 rgba(or xyzw) texture slots 
	float iX2 = (i * 2.0);
	// (iX2 + 0.0) corresponds to .x: idLeftChild, .y: aabbMin.x, .z: aabbMin.y, .w: aabbMin.z 
	// (iX2 + 1.0) corresponds to .x: idRightChild .y: aabbMax.x, .z: aabbMax.y, .w: aabbMax.z 

	ivec2 uv0 = ivec2( mod(iX2 + 0.0, 2048.0), (iX2 + 0.0) * INV_TEXTURE_WIDTH ); // data0
	ivec2 uv1 = ivec2( mod(iX2 + 1.0, 2048.0), (iX2 + 1.0) * INV_TEXTURE_WIDTH ); // data1
	
	BoxNode BN = BoxNode( texelFetch(tAABBTexture, uv0, 0), texelFetch(tAABBTexture, uv1, 0) );

        return BN;
}


//-------------------------------------------------------------------------------
float SceneIntersect( Ray r, inout Intersection intersec, out bool isRayExiting )
//-------------------------------------------------------------------------------
{
	BoxNode currentBoxNode, nodeA, nodeB, tmpNode;
	
	vec4 aabbNodeData;
	vec4 vd0, vd1, vd2, vd3, vd4, vd5, vd6, vd7;

	vec3 aabbMin, aabbMax;
	vec3 inverseDir = 1.0 / r.direction;
	vec3 normal;
	vec3 hitPos, toLightBulb;

	vec2 currentStackData, stackDataA, stackDataB, tmpStackData;
	ivec2 uv0, uv1, uv2, uv3, uv4, uv5, uv6, uv7;

	float d;
	float t = INFINITY;
        float stackptr = 0.0;	
	float bc, bd;
	float id = 0.0;
	float tu, tv;
	float triangleID = 0.0;
	float triangleU = 0.0;
	float triangleV = 0.0;
	float triangleW = 0.0;
	
	bool skip = false;
	bool triangleLookupNeeded = false;


	for (int i = 0; i < N_SPHERES; i++)
        {
		d = SphereIntersect( spheres[i].radius, spheres[i].position, r );
		if (d < t)
		{
			t = d;
			intersec.normal = (r.origin + r.direction * t) - spheres[i].position;
			intersec.emission = spheres[i].emission;
			intersec.color = spheres[i].color;
			intersec.type = spheres[i].type;
			intersec.textureID = -1;
			intersec.isDynamic = false;
		}
	}

        for (int i = 0; i < N_BOXES; i++)
        {
		d = BoxIntersect( boxes[i].minCorner, boxes[i].maxCorner, r, normal, isRayExiting );
		if (d < t)
		{
			t = d;
			intersec.normal = normalize(normal);
			intersec.emission = boxes[i].emission;
			intersec.color = boxes[i].color;
			intersec.type = boxes[i].type;
			intersec.textureID = -1;
			intersec.isDynamic = false;
		}
        }

        d = DiskIntersect( disks[0].radius, disks[0].pos, disks[0].normal, r );
	if (d < t)
	{
		t = d;
		intersec.normal = dot(disks[0].normal,r.direction) <= 0.0 ? normalize(disks[0].normal) : normalize(disks[0].normal * -1.0);
		intersec.emission = disks[0].emission;
		hitPos = r.origin + r.direction * t;
		toLightBulb = normalize(spheres[1].position - hitPos);
		
		if (dot(intersec.normal, toLightBulb) > 0.0)
		{
			intersec.color = disks[0].color;
			intersec.type = disks[0].type;
		}
		else
		{
			intersec.color = vec3(0);
			intersec.type = DIFF;
		}
		intersec.textureID = -1;
		intersec.isDynamic = false;
	}

	d = OpenCylinderIntersect( openCylinders[0].pos0, openCylinders[0].pos1, openCylinders[0].radius, r, normal );
	if (d < t)
	{
		t = d;
		intersec.normal = normalize(normal);
		intersec.emission = openCylinders[0].emission;
		hitPos = r.origin + r.direction * t;
		toLightBulb = normalize(spheres[1].position - hitPos);
		
		if (dot(intersec.normal, toLightBulb) > 0.0)
		{
			intersec.color = openCylinders[0].color;
			intersec.type = openCylinders[0].type;
		}
		else 
		{
			intersec.color = vec3(0);
			intersec.type = DIFF;
		}
		intersec.textureID = -1;
		intersec.isDynamic = false;
        }
        

	// transform ray into GLTF_Model's object space
	r.origin = vec3( uGLTF_Model_InvMatrix * vec4(r.origin, 1.0) );
	r.direction = vec3( uGLTF_Model_InvMatrix * vec4(r.direction, 0.0) );
	inverseDir = 1.0 / r.direction;


	currentBoxNode = GetBoxNode(stackptr);
	currentStackData = vec2(stackptr, BoundingBoxIntersect(currentBoxNode.data0.yzw, currentBoxNode.data1.yzw, r.origin, inverseDir));
	stackLevels[0] = currentStackData;
	
	while (true)
        {
		if (currentStackData.y < t) 
                {
                        if (currentBoxNode.data0.x < 0.0) //  < 0.0 signifies a leaf node
                        {
				// each triangle's data is encoded in 8 rgba(or xyzw) texture slots
				id = 8.0 * (-currentBoxNode.data0.x - 1.0);

				uv0 = ivec2( mod(id + 0.0, 2048.0), (id + 0.0) * INV_TEXTURE_WIDTH );
				uv1 = ivec2( mod(id + 1.0, 2048.0), (id + 1.0) * INV_TEXTURE_WIDTH );
				uv2 = ivec2( mod(id + 2.0, 2048.0), (id + 2.0) * INV_TEXTURE_WIDTH );
				
				vd0 = texelFetch(tTriangleTexture, uv0, 0);
				vd1 = texelFetch(tTriangleTexture, uv1, 0);
				vd2 = texelFetch(tTriangleTexture, uv2, 0);

				d = BVH_TriangleIntersect( vec3(vd0.xyz), vec3(vd0.w, vd1.xy), vec3(vd1.zw, vd2.x), r, tu, tv );

				if (d < t)
				{
					t = d;
					triangleID = id;
					triangleU = tu;
					triangleV = tv;
					triangleLookupNeeded = true;
				}
                        }
                        else // else this is a branch
                        {
                                nodeA = GetBoxNode(currentBoxNode.data0.x);
                                nodeB = GetBoxNode(currentBoxNode.data1.x);
                                stackDataA = vec2(currentBoxNode.data0.x, BoundingBoxIntersect(nodeA.data0.yzw, nodeA.data1.yzw, r.origin, inverseDir));
                                stackDataB = vec2(currentBoxNode.data1.x, BoundingBoxIntersect(nodeB.data0.yzw, nodeB.data1.yzw, r.origin, inverseDir));
				
				// first sort the branch node data so that 'a' is the smallest
				if (stackDataB.y < stackDataA.y)
				{
					tmpStackData = stackDataB;
					stackDataB = stackDataA;
					stackDataA = tmpStackData;

					tmpNode = nodeB;
					nodeB = nodeA;
					nodeA = tmpNode;
				} // branch 'b' now has the larger rayT value of 'a' and 'b'

				if (stackDataB.y < t) // see if branch 'b' (the larger rayT) needs to be processed
				{
					currentStackData = stackDataB;
					currentBoxNode = nodeB;
					skip = true; // this will prevent the stackptr from decreasing by 1
				}
				if (stackDataA.y < t) // see if branch 'a' (the smaller rayT) needs to be processed 
				{
					if (skip) // if larger branch 'b' needed to be processed also,
						stackLevels[int(stackptr++)] = stackDataB; // cue larger branch 'b' for future round
								// also, increase pointer by 1
					
					currentStackData = stackDataA;
					currentBoxNode = nodeA;
					skip = true; // this will prevent the stackptr from decreasing by 1
				}
                        }
		} // end if (currentStackData.y < t)

		if (!skip) 
                {
                        // decrease pointer by 1 (0.0 is root level, 24.0 is maximum depth)
                        if (--stackptr < 0.0) // went past the root level, terminate loop
                                break;
                        currentStackData = stackLevels[int(stackptr)];
                        currentBoxNode = GetBoxNode(currentStackData.x);
                }
		skip = false; // reset skip

        } // end while (true)


	if (triangleLookupNeeded)
	{
		uv0 = ivec2( mod(triangleID + 0.0, 2048.0), (triangleID + 0.0) * INV_TEXTURE_WIDTH );
		uv1 = ivec2( mod(triangleID + 1.0, 2048.0), (triangleID + 1.0) * INV_TEXTURE_WIDTH );
		uv2 = ivec2( mod(triangleID + 2.0, 2048.0), (triangleID + 2.0) * INV_TEXTURE_WIDTH );
		uv3 = ivec2( mod(triangleID + 3.0, 2048.0), (triangleID + 3.0) * INV_TEXTURE_WIDTH );
		uv4 = ivec2( mod(triangleID + 4.0, 2048.0), (triangleID + 4.0) * INV_TEXTURE_WIDTH );
		uv5 = ivec2( mod(triangleID + 5.0, 2048.0), (triangleID + 5.0) * INV_TEXTURE_WIDTH );
		uv6 = ivec2( mod(triangleID + 6.0, 2048.0), (triangleID + 6.0) * INV_TEXTURE_WIDTH );
		uv7 = ivec2( mod(triangleID + 7.0, 2048.0), (triangleID + 7.0) * INV_TEXTURE_WIDTH );
		
		vd0 = texelFetch(tTriangleTexture, uv0, 0);
		vd1 = texelFetch(tTriangleTexture, uv1, 0);
		vd2 = texelFetch(tTriangleTexture, uv2, 0);
		vd3 = texelFetch(tTriangleTexture, uv3, 0);
		vd4 = texelFetch(tTriangleTexture, uv4, 0);
		vd5 = texelFetch(tTriangleTexture, uv5, 0);
		vd6 = texelFetch(tTriangleTexture, uv6, 0);
		vd7 = texelFetch(tTriangleTexture, uv7, 0);	      

		// face normal for flat-shaded polygon look
		//intersec.normal = normalize( cross(vec3(vd0.w, vd1.xy) - vec3(vd0.xyz), vec3(vd1.zw, vd2.x) - vec3(vd0.xyz)) );
		
		// interpolated normal using triangle intersection's uv's
		triangleW = 1.0 - triangleU - triangleV;
		intersec.uv = triangleW * vec2(vd4.zw) + triangleU * vec2(vd5.xy) + triangleV * vec2(vd5.zw);
		intersec.normal = normalize(triangleW * vec3(vd2.yzw) + triangleU * vec3(vd3.xyz) + triangleV * vec3(vd3.w, vd4.xy));
		
		// transform normal back into world space
		intersec.normal = normalize(vec3(uGLTF_Model_NormalMatrix * intersec.normal));
		intersec.emission = vec3(1, 0, 1); // use this if intersec.type will be LIGHT
		intersec.color = vd6.yzw;
		
		//intersec.type = int(vd6.x);
		intersec.type = PBR_MATERIAL;
                intersec.textureID = int(vd7.x);
                intersec.isDynamic = true;
	}

	return t;

} // end float SceneIntersect( Ray r, inout Intersection intersec )



//--------------------------------------------------------------------------------------------------------
vec3 CalculateRadiance( Ray r, inout uvec2 seed )
//--------------------------------------------------------------------------------------------------------
{
        Intersection intersec;
        Sphere light = spheres[1];
	Ray firstRay;
	Ray secondaryRay;

	vec3 accumCol = vec3(0);
        vec3 mask = vec3(1);
	vec3 firstMask = vec3(1);
	vec3 secondaryMask = vec3(1);
	vec3 checkCol0 = vec3(1);
	vec3 checkCol1 = vec3(0.5);
        vec3 dirToLight;
        vec3 tdir;
	vec3 metallicRoughness = vec3(0);
	vec3 x, n, nl;
        
	float t;
        float nc, nt, ratioIoR, Re, Tr;
        float weight;
        float thickness = 0.1;

	int diffuseCount = 0;

	bool bounceIsSpecular = true;
	bool sampleLight = false;
	bool firstTypeWasREFR = false;
	bool reflectionTime = false;
	bool firstTypeWasDIFF = false;
	bool shadowTime = false;
	bool firstTypeWasCOAT = false;
	bool isRayExiting = false;

	
        for (int bounces = 0; bounces < 6; bounces++)
	{

		t = SceneIntersect(r, intersec, isRayExiting);
		
		/*
		if (t == INFINITY)
		{
                        break;
		}
		*/
		

		if (intersec.type == LIGHT)
		{	
			if (bounces == 0)
			{
				accumCol = mask * intersec.emission;
				break;
			}

			if (firstTypeWasDIFF)
			{
				if (!shadowTime) 
				{
					accumCol = mask * intersec.emission;
					
					// start back at the diffuse surface, but this time follow shadow ray branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					shadowTime = true;
					bounceIsSpecular = false;
					sampleLight = true;
					// continue with the shadow ray
					continue;
				}
				
				break;		
			}

			if (firstTypeWasREFR)
			{
				if (!reflectionTime) 
				{
					accumCol = mask * intersec.emission;
					
					// start back at the refractive surface, but this time follow reflective branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					reflectionTime = true;
					bounceIsSpecular = true;
					sampleLight = false;
					// continue with the reflection ray
					continue;
				}

				accumCol += mask * intersec.emission; // add reflective result to the refractive result (if any)
				break;	
			}

			if (firstTypeWasCOAT)
			{
				if (!shadowTime) 
				{
					accumCol = mask * intersec.emission;

					// start back at the diffuse surface, but this time follow shadow ray branch
					r = secondaryRay;
					r.direction = normalize(r.direction);
					mask = secondaryMask;
					// set/reset variables
					shadowTime = true;
					bounceIsSpecular = false;
					sampleLight = true;
					// continue with the shadow ray
					continue;
				}

				if (!reflectionTime) 
				{
					// start back at the refractive surface, but this time follow reflective branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					reflectionTime = true;
					bounceIsSpecular = true;
					sampleLight = false;
					// continue with the reflection ray
					continue;
				}

				accumCol += mask * intersec.emission; // add reflective result to the diffuse result
				break;	
			}

			accumCol = mask * intersec.emission; // looking at light through a reflection
			// reached a light, so we can exit
			break;

		} // end if (intersec.type == LIGHT)


		if (intersec.type == SPOT_LIGHT)
		{	

			if (bounces == 0)
			{
				accumCol = mask * clamp(intersec.emission, 0.0, 10.0);
				break;
			}

			if (firstTypeWasDIFF)
			{
				if (!shadowTime) 
				{
					if (sampleLight)
						accumCol = mask * intersec.emission * 0.5;

					// start back at the diffuse surface, but this time follow shadow ray branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					shadowTime = true;
					bounceIsSpecular = false;
					sampleLight = true;
					// continue with the shadow ray
					continue;
				}

				accumCol += mask * intersec.emission * 0.5;
				
				break;
			}

			if (firstTypeWasREFR)
			{
				if (!reflectionTime) 
				{
					if (sampleLight)
						accumCol = mask * intersec.emission;
					else if (bounceIsSpecular)
						accumCol = mask * clamp(intersec.emission, 0.0, 10.0);
					
					// start back at the refractive surface, but this time follow reflective branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					reflectionTime = true;
					bounceIsSpecular = true;
					sampleLight = false;
					// continue with the reflection ray
					continue;
				}

				if (sampleLight)
				{
					accumCol += mask * intersec.emission; // add reflective result to the refractive result (if any)
					break;
				}	
				else if (bounceIsSpecular)
				{
					accumCol += mask * clamp(intersec.emission, 0.0, 10.0);
					break;
				}
			}

			if (firstTypeWasCOAT)
			{
				if (!shadowTime) 
				{
					if (sampleLight)
						accumCol = mask * intersec.emission * 0.5;

					// start back at the diffuse surface, but this time follow shadow ray branch
					r = secondaryRay;
					r.direction = normalize(r.direction);
					mask = secondaryMask;
					// set/reset variables
					shadowTime = true;
					bounceIsSpecular = false;
					sampleLight = true;
					// continue with the shadow ray
					continue;
				}

				if (!reflectionTime)
				{
					// add initial shadow ray result to secondary shadow ray result (if any) 
					accumCol += mask * intersec.emission * 0.5;

					// start back at the coat surface, but this time follow reflective branch
					r = firstRay;
					r.direction = normalize(r.direction);
					mask = firstMask;
					// set/reset variables
					reflectionTime = true;
					bounceIsSpecular = true;
					sampleLight = false;
					// continue with the reflection ray
					continue;
				}

				// add reflective result to the diffuse result
				if (sampleLight)
					accumCol += mask * intersec.emission;
				if (bounceIsSpecular)
					accumCol += mask * clamp(intersec.emission, 0.0, 200.0);
				
				break;	
			}

			if (sampleLight)
				accumCol = mask * intersec.emission; // looking at light through a reflection
			if (bounceIsSpecular)
				accumCol = mask * clamp(intersec.emission, 0.0, 1.0); // looking at light through a reflection
			
			// reached a light, so we can exit
			break;
		} // end if (intersec.type == SPOTLIGHT)

		
		// if we get here and sampleLight is still true, shadow ray failed to find a light source
		if (sampleLight) 
		{
			if (firstTypeWasDIFF && !shadowTime) 
			{
				// start back at the diffuse surface, but this time follow shadow ray branch
				r = firstRay;
				r.direction = normalize(r.direction);
				mask = firstMask;
				// set/reset variables
				shadowTime = true;
				bounceIsSpecular = false;
				sampleLight = true;
				// continue with the shadow ray
				continue;
			}

			if (firstTypeWasREFR && !reflectionTime) 
			{
				// start back at the refractive surface, but this time follow reflective branch
				r = firstRay;
				r.direction = normalize(r.direction);
				mask = firstMask;
				// set/reset variables
				reflectionTime = true;
				bounceIsSpecular = true;
				sampleLight = false;
				// continue with the reflection ray
				continue;
			}

			if (firstTypeWasCOAT && !shadowTime) 
			{
				// start back at the diffuse surface, but this time follow shadow ray branch
				r = secondaryRay;
				r.direction = normalize(r.direction);
				mask = secondaryMask;
				// set/reset variables
				shadowTime = true;
				bounceIsSpecular = false;
				sampleLight = true;
				// continue with the shadow ray
				continue;
			}

			if (firstTypeWasCOAT && !reflectionTime) 
			{
				// start back at the coat surface, but this time follow reflective branch
				r = firstRay;
				r.direction = normalize(r.direction);
				mask = firstMask;
				// set/reset variables
				reflectionTime = true;
				bounceIsSpecular = true;
				sampleLight = false;
				// continue with the reflection ray
				continue;
			}

			// nothing left to calculate, so exit	
			break;
		}
		
		
		// useful data 
		n = normalize(intersec.normal);
                nl = dot(n, r.direction) < 0.0 ? normalize(n) : normalize(-n);
		x = r.origin + r.direction * t;

		if (intersec.type == PBR_MATERIAL)
		{
			vec3 S = normalize( cross( abs(nl.y) < 0.9 ? vec3(0, 1, 0) : vec3(0, 0, 1), nl ) );
			vec3 T = cross(nl, S);
			vec3 N = normalize( nl );
			// invert S, T when the UV direction is backwards (from mirrored faces),
			// otherwise it will do the normal mapping backwards.
			/* vec3 NfromST = cross( S, T );
			if( dot( NfromST, N ) < 0.0 )
			{
				S *= -1.0;
				T *= -1.0;
			} */

			mat3 tsn = mat3( S, T, N );
			vec3 mapN = texture(tNormalMap, intersec.uv).xyz * 2.0 - 1.0;
			vec2 normalScale = vec2(1.0, 1.0);
			mapN.xy *= normalScale;
			nl = normalize( tsn * mapN );

			intersec.color = texture(tAlbedoMap, intersec.uv).rgb;
			intersec.color = pow(intersec.color,vec3(2.2));
			
			intersec.emission = texture(tEmissiveMap, intersec.uv).rgb;
			intersec.emission = pow(intersec.emission,vec3(2.2));
			
			float maxEmission = max(intersec.emission.r, max(intersec.emission.g, intersec.emission.b));
			if (bounceIsSpecular && maxEmission > 0.01) //if (rand(seed) < maxEmission)
			{
				accumCol = mask * intersec.emission;
				break;
			}

			intersec.type = COAT;

			metallicRoughness = texture(tMetallicRoughnessMap, intersec.uv).rgb;
			if (metallicRoughness.b > 0.0)
				intersec.type = SPEC;
		}
		
		    
                if (intersec.type == DIFF || intersec.type == CHECK) // Ideal DIFFUSE reflection
                {
			diffuseCount++;

			if ( intersec.type == CHECK )
			{
				float q = clamp( mod( dot( floor(x.xz * 0.04), vec2(1.0) ), 2.0 ) , 0.0, 1.0 );
				intersec.color = checkCol0 * q + checkCol1 * (1.0 - q);	
			}
			
			mask *= intersec.color;

                        bounceIsSpecular = false;

                        if (diffuseCount == 1 && !firstTypeWasDIFF && !firstTypeWasREFR)
			{	
				// save intersection data for future shadowray trace
				firstTypeWasDIFF = true;
				dirToLight = sampleSphereLight(x, nl, light, dirToLight, weight, seed);
				firstMask = mask * weight;
                                firstRay = Ray( x, normalize(dirToLight) ); // create shadow ray pointed towards light
				firstRay.origin += nl * uEPS_intersect;

				// choose random Diffuse sample vector
				r = Ray( x, normalize(randomCosWeightedDirectionInHemisphere(nl, seed)) );
				r.origin += nl * uEPS_intersect;
				continue;
			}
			else if ((firstTypeWasREFR || reflectionTime) && rand(seed) < 0.5)
			{
				// choose random Diffuse sample vector
				r = Ray( x, normalize(randomCosWeightedDirectionInHemisphere(nl, seed)) );
				r.origin += nl * uEPS_intersect;
				continue;
			}
                        
			dirToLight = sampleSphereLight(x, nl, light, dirToLight, weight, seed);
			mask *= weight;

			r = Ray( x, normalize(dirToLight) );
			r.origin += nl * uEPS_intersect;
			sampleLight = true;
			continue;
                        
		} // end if (intersec.type == DIFF)
		
                if (intersec.type == SPEC)  // Ideal SPECULAR reflection
                {
			mask *= intersec.color;

			vec3 reflectVec = reflect(r.direction, nl);
			vec3 glossyVec = randomDirectionInHemisphere(nl, seed);
			r = Ray( x, mix(reflectVec, glossyVec, metallicRoughness.g) );
			r.direction = normalize(r.direction);
			r.origin += nl * uEPS_intersect;
			
			//bounceIsSpecular = true;
                        continue;
                }

                if (intersec.type == REFR)  // Ideal dielectric REFRACTION
		{
			nc = 1.0; // IOR of Air
			nt = 1.5; // IOR of common Glass
			Re = calcFresnelReflectance(r.direction, n, nc, nt, ratioIoR);
			Tr = 1.0 - Re;
			
			if (!firstTypeWasREFR && diffuseCount == 0)
			{	
				// save intersection data for future reflection trace
				firstTypeWasREFR = true;
				firstMask = mask * Re;
				firstRay = Ray( x, reflect(r.direction, nl) ); // create reflection ray from surface
				firstRay.origin += nl * uEPS_intersect;
				mask *= Tr;
			}
			else if (bounceIsSpecular && n == nl && rand(seed) < Re)
			{
				r = Ray( x, reflect(r.direction, nl) ); // reflect ray from surface
				r.origin += nl * uEPS_intersect;
				continue;
			}

			// transmit ray through surface

			// is ray leaving a solid object from the inside? 
			// If so, attenuate ray color with object color by how far ray has travelled through the medium
			if (isRayExiting)
			{
				mask *= exp(log(intersec.color) * thickness * t);
			}
			
			tdir = refract(r.direction, nl, ratioIoR);
			r = Ray(x, normalize(tdir));
			r.origin -= nl * uEPS_intersect;
			
			if (bounces == 1)
				bounceIsSpecular = true; // turn on refracting caustics

			continue;
			
		} // end if (intersec.type == REFR)
		
		if (intersec.type == COAT)  // Diffuse object underneath with ClearCoat on top
		{
			nc = 1.0; // IOR of Air
			nt = 1.4; // IOR of Clear Coat
			Re = calcFresnelReflectance(r.direction, n, nc, nt, ratioIoR);
			Tr = 1.0 - Re;

			if (!firstTypeWasREFR && !firstTypeWasCOAT && diffuseCount == 0)
			{	
				// save intersection data for future reflection trace
				firstTypeWasCOAT = true;
				firstMask = mask * Re;
				firstRay = Ray( x, reflect(r.direction, nl) ); // create reflection ray from surface
				firstRay.origin += nl * uEPS_intersect;
				mask *= Tr;
			}
			else if (bounceIsSpecular && rand(seed) < Re)
			{
				r = Ray( x, reflect(r.direction, nl) ); // reflect ray from surface
				r.origin += nl * uEPS_intersect;
				continue;
			}

			diffuseCount++;

			mask *= intersec.color;
			
			bounceIsSpecular = false;

			if (firstTypeWasCOAT && diffuseCount == 1)
                        {
                                // save intersection data for future shadowray trace
				dirToLight = sampleSphereLight(x, nl, light, dirToLight, weight, seed);
				secondaryMask = mask * weight;
                                secondaryRay = Ray( x, normalize(dirToLight) ); // create shadow ray pointed towards light
				secondaryRay.origin += nl * uEPS_intersect;

				// choose random Diffuse sample vector
				r = Ray( x, normalize(randomCosWeightedDirectionInHemisphere(nl, seed)) );
				r.origin += nl * uEPS_intersect;
				continue;
                        }
			else if ((firstTypeWasREFR || reflectionTime) && rand(seed) < 0.5)
			{
				// choose random Diffuse sample vector
				r = Ray( x, normalize(randomCosWeightedDirectionInHemisphere(nl, seed)) );
				r.origin += nl * uEPS_intersect;
				continue;
			}
                        
			dirToLight = sampleSphereLight(x, nl, light, dirToLight, weight, seed);
			mask *= weight;
			
			r = Ray( x, normalize(dirToLight) );
			r.origin += nl * uEPS_intersect;

			sampleLight = true;
			continue;
                        
		} //end if (intersec.type == COAT)
		
	} // end for (int bounces = 0; bounces < 6; bounces++)
	

	return max(vec3(0), accumCol);
	    
} // end vec3 CalculateRadiance( Ray r, inout uvec2 seed )


//-----------------------------------------------------------------------
void SetupScene(void)
//-----------------------------------------------------------------------
{
	vec3 z  = vec3(0);          
	vec3 L1 = vec3(0.5, 0.7, 1.0) * 0.01;// Blueish sky light
	vec3 L2 = vec3(1.0, 1.0, 1.0) * 300.0;// Bright white light bulb
	
	spheres[0] = Sphere( 10000.0,     vec3(0, 0, 0), L1, z, LIGHT, false);//spherical white Light1
	spheres[1] = Sphere( 3.0, vec3(-10, 100, -50), L2, z, SPOT_LIGHT, false);//spotlight
	spheres[2] = Sphere( 4000.0, vec3(0, -4000, 0), z, vec3(0.4, 0.4, 0.4), CHECK, false);//Checkered Floor
        
        vec3 spotLightTarget = uGLTF_Model_Position;
        vec3 spotLightPos = spheres[1].position;
	vec3 spotLightDir = normalize(spotLightTarget - spotLightPos);
	openCylinders[0] = OpenCylinder( spotLightPos - (spotLightDir * spheres[1].radius) * 2.0, spotLightPos + (spotLightDir * spheres[1].radius) * 5.0, 
					   spheres[1].radius * 1.5, z, vec3(1), SPEC, true);//metal open Cylinder
        disks[0] = Disk( spheres[1].radius * 1.5, spotLightPos - (spotLightDir * spheres[1].radius * 2.0), spotLightDir, z, vec3(0.9, 0.9, 0.9), SPEC, true);//metal disk
        	
	boxes[0] = Box( vec3(-20.0,11.0,-110.0), vec3(70.0,18.0,-20.0), z, vec3(0.2,0.9,0.7), REFR, false);//Glass Box
	boxes[1] = Box( vec3(-14.0,13.0,-104.0), vec3(64.0,16.0,-26.0), z, vec3(0),           DIFF, false);//Inner Box
}


//#include <pathtracing_main>

// tentFilter from Peter Shirley's 'Realistic Ray Tracing (2nd Edition)' book, pg. 60		
float tentFilter(float x)
{
        if (x < 0.5) 
                return sqrt(2.0 * x) - 1.0;
        else return 1.0 - sqrt(2.0 - (2.0 * x));
}

void main( void )
{
        // not needed, three.js has a built-in uniform named cameraPosition
        //vec3 camPos   = vec3( uCameraMatrix[3][0],  uCameraMatrix[3][1],  uCameraMatrix[3][2]);
        
        vec3 camRight   = vec3( uCameraMatrix[0][0],  uCameraMatrix[0][1],  uCameraMatrix[0][2]);
        vec3 camUp      = vec3( uCameraMatrix[1][0],  uCameraMatrix[1][1],  uCameraMatrix[1][2]);
        vec3 camForward = vec3(-uCameraMatrix[2][0], -uCameraMatrix[2][1], -uCameraMatrix[2][2]);
        
        // seed for rand(seed) function
        uvec2 seed = uvec2(uFrameCounter, uFrameCounter + 1.0) * uvec2(gl_FragCoord);

        vec2 pixelPos = vec2(0);
        vec2 pixelOffset = vec2(0);

        float x = rand(seed);
        float y = rand(seed);

        //if (!uCameraIsMoving)
        {
                pixelOffset.x = tentFilter(x);
                pixelOffset.y = tentFilter(y);
        }
        
        // pixelOffset ranges from -1.0 to +1.0, so only need to divide by half resolution
        pixelOffset /= (uResolution * 1.0); // normally this is * 0.5, but for dynamic scenes, * 1.0 looks sharper

        // we must map pixelPos into the range -1.0 to +1.0
	pixelPos = (gl_FragCoord.xy / uResolution) * 2.0 - 1.0;
        pixelPos += pixelOffset;

        vec3 rayDir = normalize( pixelPos.x * camRight * uULen + pixelPos.y * camUp * uVLen + camForward );
        
        // depth of field
        vec3 focalPoint = uFocusDistance * rayDir;
        float randomAngle = rand(seed) * TWO_PI; // pick random point on aperture
        float randomRadius = rand(seed) * uApertureSize;
        vec3  randomAperturePos = ( cos(randomAngle) * camRight + sin(randomAngle) * camUp ) * sqrt(randomRadius);
        // point on aperture to focal point
        vec3 finalRayDir = normalize(focalPoint - randomAperturePos);
        
        Ray ray = Ray( cameraPosition + randomAperturePos, finalRayDir );

        SetupScene(); 

        // perform path tracing and get resulting pixel color
        vec3 pixelColor = CalculateRadiance( ray, seed );
        
	vec4 previousImage = texelFetch(tPreviousTexture, ivec2(gl_FragCoord.xy), 0);
	vec3 previousColor = previousImage.rgb;

	if (uCameraIsMoving)
	{
                previousColor *= 0.5; // motion-blur trail amount (old image)
                pixelColor *= 0.5; // brightness of new image (noisy)
        }
	else
	{
                previousColor *= 0.9; // motion-blur trail amount (old image)
                pixelColor *= 0.1; // brightness of new image (noisy)
        }
	
        pc_fragColor = vec4( pixelColor + previousColor, 1.0 );	
}
