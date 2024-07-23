#define PI 3.14159265359

uniform float u_eps;
uniform float u_maxDis;
uniform int u_maxSteps;

uniform float u_time;

uniform vec3 u_camPos;
uniform mat4 u_camToWorldMat;
uniform mat4 u_camInvProjMat;

uniform vec2 u_resolution;

uniform vec3 u_sunDirection;
uniform vec3 u_sunColor;
uniform float u_sunStrength;

uniform float u_ambientStrength;
uniform float u_shapeSize;
uniform float u_densityThreshold;
uniform float u_transmittanceThreshold;

uniform int u_cloudSteps;
uniform float u_cloudStepDelta;

uniform int u_lightSteps;
uniform float u_lightStepDelta;


float hash( float n )
{
    return fract( n*17.0*fract( n*0.3183099 ) );
}

float noise( vec3 x )
{
    vec3 p = floor(x);
    vec3 w = fract(x);

    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);

    float n = p.x + 317.0*p.y + 157.0*p.z;

    float a = hash(n+0.0);
    float b = hash(n+1.0);
    float c = hash(n+317.0);
    float d = hash(n+318.0);
    float e = hash(n+157.0);
    float f = hash(n+158.0);
    float g = hash(n+474.0);
    float h = hash(n+475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return -1.0+2.0*(k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z);
}

float fbm_8( vec3 x )
{
    float G = .5;
    float f = 1.0;
    float a = 1.0;
    float t = 0.0;

    for( int i=0; i<8; i++ )
    {
        t += a * noise( f * x );
        f *= 2.0;
        a *= G;
    }

    return t;
}

float SampleFBM(vec3 pos) {
    return max(min(fbm_8(pos), 1.), 0.);
}


float SampleCoudDensity(float cloudSDF, vec3 worldPos, float curTime) {
    float cloud = smoothstep(0.0, 50., -cloudSDF) * 0.011;

    vec3 velocity = vec3(-5, 0, 2);

    if(cloud > 0.0) {
        vec3 samplePos = worldPos + velocity * curTime;
        float dencitySample = SampleFBM(samplePos * u_shapeSize);
        cloud = dencitySample * smoothstep(0.0, 15., -cloudSDF);
    }

    return cloud * 0.5;
}

float sdBox( vec3 p, vec3 b ) {
    vec3 q = abs(p) - b;
    return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float smin( float a, float b, float k ) {
    k *= 2.0;
    float x = b-a;
    return 0.5*( a+b-sqrt(x*x+k*k) );
}

float sdCutSphere( vec3 p, float r, float h ) {
    // sampling independent computations (only depend on shape)
    float w = sqrt(r*r-h*h);

    // sampling dependant computations
    vec2 q = vec2( length(p.xz), p.y );
    float s = max( (h-r)*q.x*q.x+w*w*(h+r-2.0*q.y), h*q.x-w*q.y );
    return (s<0.0) ? length(q)-r :
    (q.x<w) ? h - q.y     :
    length(q-vec2(w,h));
}

float sdEllipsoid( vec3 p, vec3 r )
{
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

float GetSceneDistance(vec3 point) {

    float sdfValue = sdCutSphere(point, 60.0, -40.0);
    sdfValue = smin(sdfValue, sdCutSphere(point - vec3(60.0, -20.0, 0.0), 40.0, -20.0), 0.1);

    //return sdfValue;

    //return sdBox(point, vec3(50.));

    return sdEllipsoid(point, vec3(50., 30., 30.));
}

float RayMarch(vec3 ray_origin, vec3 ray_dir) {
    float distance = 0.;

    for(int i = 0; i < u_maxSteps; i++)
    {
        vec3 p = ray_origin + ray_dir * distance;
        float ds = GetSceneDistance(p);
        distance += ds;
        if(distance > u_maxDis || ds < u_eps)
        break;  // hit object or out of scene
    }
    return distance;
}

float HGPhase(float g, float mu) {
    float gg = g * g;
    return (1.0 / (4.0 * PI))  * ((1.0 - gg) / pow(1.0 + gg - 2.0 * g * mu, 1.5));
}

float PhaseFrostbite(float mu) {
    return mix(HGPhase(0.5, mu), HGPhase(-0.5, mu), 0.4);
}

vec3 MultipleOctaveScattering(float density, float mu) {
    float attenuation = 0.2;
    float contribution = 0.2;
    float phaseAttenuation = 0.5;

    float a = 1.0;
    float b = 1.0;
    float c = 1.0;
    float g = 0.85;
    const float scatteringOctaves = 2.0;

    vec3 luminance = vec3(0.0);

    for (float i = 0.0; i < scatteringOctaves; i++) {
        float phaseFunction = PhaseFrostbite(mu);
        float beers = exp(-density * a);

        luminance += b * phaseFunction * beers;

        a *= attenuation;
        b *= contribution;
        c *= (1.0 - phaseAttenuation);
    }
    return vec3(luminance);
}

vec3 SampleLightEnergy(vec3 rayOrigin, float mu, float curTime) {
    float sampleColudDensity = 0.0;
    float distance = 0.0;

    vec3 samplePos;
    float cloudSDF;

    for (int i = 0; i < u_lightSteps; i++) {
        samplePos = rayOrigin + distance * u_sunDirection;
        cloudSDF = GetSceneDistance(samplePos);

        sampleColudDensity += SampleCoudDensity(cloudSDF, samplePos, curTime) * u_lightStepDelta;
        distance += u_lightStepDelta;

        if (cloudSDF > 0.0 && i!= 0 ) {
            break;
        }
    }

    vec3 beersLaw = MultipleOctaveScattering(sampleColudDensity, mu);
    //vec3 beersLaw = exp(-sampleColudDensity) * PhaseFrostbite(mu) * vec3(1.);
    vec3 powder = 1.0 - exp(-sampleColudDensity * 2.0 * vec3(1.));

    return beersLaw * powder;
}

vec4 GetColor(vec3 rayOrigin, vec3 rayDirection, float distTravelled, float curTime) {
    float cloudTransmittance = 1.0;
    vec3 cloudScattering = vec3(0.0);

    vec3 samplePos;
    vec3 Scatering;
    vec3 integScatt;

    float sceneSDF;
    float currentStepLength;
    float cloudDensity;
    float sampleTransmittance;


    vec3 ambientLight = u_ambientStrength * u_sunColor;
    vec3 sunLight = u_sunStrength * u_sunColor;

    float mu = dot(rayDirection, u_sunDirection);

    for (int i = 0; i < u_cloudSteps; i++) {
        if (distTravelled > u_maxDis) {
            break;
        }

        samplePos = rayOrigin + rayDirection * distTravelled;
        sceneSDF = GetSceneDistance(samplePos);

        if (sceneSDF < 0.) {
            cloudDensity = SampleCoudDensity(sceneSDF, samplePos, curTime);

            if (cloudDensity > u_densityThreshold) {
                Scatering = ambientLight + sunLight * SampleLightEnergy(samplePos, mu, curTime);

                // integScatt = (Scatering - Scatering * exp(-cloudDensity * u_cloudStepDelta)) / cloudDensity;
                integScatt = (Scatering - Scatering * exp(-cloudDensity * u_cloudStepDelta));

                cloudScattering += cloudTransmittance * integScatt;
                cloudTransmittance *= exp(-cloudDensity * u_cloudStepDelta);

                if (cloudTransmittance <= u_transmittanceThreshold) {
                    cloudTransmittance = 0.0;
                    break;
                }
            }
        }

        distTravelled += u_cloudStepDelta;

    }

    return vec4(pow(cloudScattering, vec3(1.0/2.2)), 1. - cloudTransmittance);
}


void main( ) {
    // Calculate uvs
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution.xy);
    uv = vec2(uv.x / u_resolution.x, uv.y / u_resolution.y);

    // calculate ray origin and direction
    vec3 rayOrigin = vec3(u_camPos);
    vec3 rayDir = (u_camInvProjMat * vec4(uv, 0, 1)).xyz;
    rayDir = (u_camToWorldMat * vec4(rayDir, 0)).xyz;
    rayDir = normalize(rayDir);

    float disTraveled = RayMarch(rayOrigin, rayDir);

    if (disTraveled >= u_maxDis) {
        gl_FragColor = vec4(0.);
    } else {
        gl_FragColor = GetColor(rayOrigin, rayDir, disTraveled, u_time);
    }

}