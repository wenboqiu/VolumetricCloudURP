#ifndef CLOUDS_INCLUDED
#define CLOUDS_INCLUDED
#include <HLSLSupport.cginc>
//modify to skybox


uniform float4 _CameraWS;

uniform sampler3D _ShapeTexture;
uniform sampler3D _DetailTexture;
uniform sampler2D _WeatherTexture;
uniform sampler2D _CurlNoise;
uniform sampler2D _BlueNoise;
uniform float4 _BlueNoise_TexelSize;
uniform float _SampleMultiplier;

uniform float3 _SunDir;
uniform float3 _PlanetCenter;
uniform float3 _SunColor;

uniform float3 _CloudBaseColor;
uniform float3 _CloudTopColor;

uniform float3 _ZeroPoint;
uniform float _SphereSize;
uniform float2 _CloudHeightMinMax;
uniform float _Thickness;

uniform float _Coverage;
uniform float _AmbientLightFactor;
uniform float _SunLightFactor;
uniform float _HenyeyGreensteinGForward;
uniform float _HenyeyGreensteinGBackward;
uniform float _LightStepLength;
uniform float _LightConeRadius;

uniform float _Density;

uniform float _Scale;
uniform float _DetailScale;
uniform float _WeatherScale;
uniform float _CurlDistortScale;
uniform float _CurlDistortAmount;

uniform float _CloudSpeed;
uniform float3 _WindDirection;
uniform float2 _CoverageWindOffset;

uniform float2 _LowFreqMinMax;
uniform float _HighFreqModifier;

uniform int _Steps;

// #define BIG_STEP 3.0

// https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection
float3 findRayStartPos(float3 rayOrigin, float3 rayDirection, float3 sphereCenter, float radius)
{
	float3 l = rayOrigin - sphereCenter;
	float a = 1.0;
	float b = 2.0 * dot(rayDirection, l);
	float c = dot(l, l) - pow(radius, 2);
	float D = pow(b, 2) - 4.0 * a * c;
	if (D < 0.0)
	{
		return rayOrigin;
	}
	else if (abs(D) - 0.00005 <= 0.0)
	{
		return rayOrigin + rayDirection * (-0.5 * b / a);
	}
	else
	{
		float q = 0.0;
		if (b > 0.0)
		{
			q = -0.5 * (b + sqrt(D));
		}
		else
		{
			q = -0.5 * (b - sqrt(D));
		}
		float h1 = q / a;
		float h2 = c / q;
		float2 t = float2(min(h1, h2), max(h1, h2));
		if (t.x < 0.0) {
			t.x = t.y;
			if (t.x < 0.0) {
				return rayOrigin;
			}
		}
		return rayOrigin + t.x * rayDirection;
	}
}

// returns height fraction [0, 1] for point in cloud
// Fractional value for sample position in the cloud layer
float GetHeightFractionForPoint(float3 pos)
{
	return saturate((distance(pos,  _PlanetCenter) - (_SphereSize + _CloudHeightMinMax.x)) / _Thickness);
}

float beerLaw(float density)
{
	float d = -density * _Density;
	return max(exp(d), exp(d * 0.5)*0.7);
}

float HenyeyGreensteinPhase(float cosAngle, float g)
{
	float g2 = g * g;
	return ((1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosAngle, 1.5)) / 4.0 * 3.1415;
}

float powderEffect(float density, float cosAngle)
{
	float powder = 1.0 - exp(-density * 2.0);
	return lerp(1.0f, powder, saturate((-cosAngle * 0.5f) + 0.5f));
}

float CalculateLightEnergy(float density, float cosAngle, float powderDensity)
{
	float beerPowder = 2.0 * beerLaw(density) * powderEffect(powderDensity, cosAngle);
	float HG = max(HenyeyGreensteinPhase(cosAngle, _HenyeyGreensteinGForward), HenyeyGreensteinPhase(cosAngle, _HenyeyGreensteinGBackward)) * 0.07 + 0.8;
	return beerPowder * HG;
}

//这个公式相对于上一个的问题在于某些角度云的颜色偏暗
float GetLightEnergy(float density, float cosAngle, float powderDensity){
	float beer_laws = exp( -density);
    
	float powdered_sugar = 1.0 - exp( -2.0 * powderDensity);

	float hg = HenyeyGreensteinPhase(cosAngle, 0.2);
    
	float totalEnergy = 2.0 * beer_laws * hg * powdered_sugar;

	return totalEnergy;
}

// from GPU Pro 7 - remaps value from one range to other range
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

// samples the gradient
float SampleGradient(float4 gradient, float height)
{
	return smoothstep(gradient.x, gradient.y, height) - smoothstep(gradient.z, gradient.w, height);
}

float GetDensityHeightGradientForPoint(float height_fraction, float3 weather_data)
{
	float cloudType = weather_data.g;

	const float4 CloudGradient1 = float4(0.0, 0.065, 0.203, 0.371); //stratus
	const float4 CloudGradient2 = float4(0.0, 0.156, 0.468, 0.674); //cumulus
	const float4 CloudGradient3 = float4(0.0, 0.188, 0.818, 1); //cumulonimbus

	float4 gradient = lerp(lerp(CloudGradient1, CloudGradient2, cloudType * 2.0), CloudGradient3, saturate(cloudType - 0.5) * 2.0);
	
	return SampleGradient(gradient, height_fraction);
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

float weatherDensity(float3 weatherData) // Gets weather density from weather texture sample and adds 1 to it.
{
	return weatherData.b + 1.0;
}

// samples weather texture
float3 sampleWeather(float3 pos) {
	float3 weatherData = tex2Dlod(_WeatherTexture, float4((pos.xz + _CoverageWindOffset) * _WeatherScale / 10.0, 0, 0)).rgb;
	weatherData.r = saturate(weatherData.r - _Coverage);
	return weatherData;
}

float3 GetWeatherData(float3 pos)
{
	float2 uv = (pos.xz + _CoverageWindOffset) * _WeatherScale / 10.0;
	// float2 uv = unit * 0.5 + 0.5;
	float3 weatherData = tex2Dlod(_WeatherTexture, float4(uv, 0.0, 0.0));
	weatherData.r = saturate(weatherData.r - _Coverage); //c#中coverage 越大，这里的_Coverage越小，需要减少的值越少
	return weatherData;
}

float SampleCloudDensity(float3 pos, float height_fraction, float3 weatherData, float mip_level, bool is_cheap)
{	
	// cloud_top offset pushes the tops of the clouds along this wind direction by this many units
	float cloud_top_offset = 500;
	
	// Skew in wind direction
	pos += height_fraction * _WindDirection * cloud_top_offset;

	// Animate clouds in wind direction and add a small upward bias to the wind direction
	pos += (_WindDirection + float3(0.0, 1.0, 0.0)) * _Time * _CloudSpeed;

	// Read the low-frequency Perlin-Worley noise
	float3 low_frequency_noises = tex3Dlod(_ShapeTexture, float4(pos * _Scale, mip_level)).rgb;

	// define the base cloud shape
	float base_cloud = Remap( low_frequency_noises.r * pow(1.2 - height_fraction, 0.1), _LowFreqMinMax.x, _LowFreqMinMax.y, 0.0, 1.0); // pick certain range from sample texture

	// Get the density-height gradient using the density height function explained in Section 4.3.2
	float density_height_gradient = GetDensityHeightGradientForPoint(height_fraction, weatherData);

	// Apply the height function to the base cloud shape
	base_cloud *= density_height_gradient;

	// Cloud coverage is stored in weather data's red channel
	float cloud_coverage = weatherData.r;

	// Use remap to apply the cloud coverage attribute
	float base_cloud_with_coverage = Remap(base_cloud, saturate(height_fraction / cloud_coverage), 1.0, 0.0, 1.0);

	// Multiply the result by the cloud coverage attribute so that smaller clouds are lighter and more aesthetically pleasing
	base_cloud_with_coverage *= cloud_coverage;

	if (base_cloud_with_coverage > 0.0 && !is_cheap) // If cloud sample > 0 then erode it with detail noise
	{
		float3 curlNoise = mad(tex2Dlod(_CurlNoise, float4(pos.xz * _CurlDistortScale, 0, 0)).rgb, 2.0, -1.0); // sample Curl noise and transform it from [0, 1] to [-1, 1]
		pos += float3(curlNoise.r, curlNoise.b, curlNoise.g) * height_fraction * _CurlDistortAmount; // distort position with curl noise

		float detailNoise = tex3Dlod(_DetailTexture, float4(pos * _DetailScale, mip_level)).r; // Sample detail noise

		float highFreqNoiseModifier = lerp(1.0 - detailNoise, detailNoise, saturate(height_fraction * 10.0)); // At lower cloud levels invert it to produce more wispy shapes and higher billowy

		base_cloud_with_coverage = Remap(base_cloud_with_coverage, highFreqNoiseModifier * _HighFreqModifier, 1.0, 0.0, 1.0); // Erode cloud edges
	}

	return max(base_cloud_with_coverage * _SampleMultiplier, 0.0);
}

float SampleCloudDensityAlongCone(float3 pos, int mip_level, float3 lightDir)
{
	const float3 RandomUnitSphere[5] = // precalculated random vectors
	{
		{ -0.6, -0.8, -0.2 },
		{ 1.0, -0.3, 0.0 },
		{ -0.7, 0.0, 0.7 },
		{ -0.2, 0.6, -0.8 },
		{ 0.4, 0.3, 0.9 }
	};

	float heightFraction;
	float densityAlongCone = 0.0;
	const int steps = 5; // light cone step count
	float3 weatherData;

	for (int i = 0; i < steps; i++) {
		pos += lightDir * _LightStepLength; // march forward

		float3 randomOffset = RandomUnitSphere[i] * _LightStepLength * _LightConeRadius * ((float)(i + 1));

		float3 p = pos + randomOffset; // light sample point
		// sample cloud
		heightFraction = GetHeightFractionForPoint(p); 
		weatherData = sampleWeather(p);
		densityAlongCone += SampleCloudDensity(p, heightFraction, weatherData, mip_level + 1, true);// * weatherDensity(weatherData);
	}

	pos += 32.0 * _LightStepLength * lightDir; // light sample from further away
	weatherData = sampleWeather(pos);
	heightFraction = GetHeightFractionForPoint(pos);
	densityAlongCone += SampleCloudDensity(pos, heightFraction, weatherData, mip_level + 2, false);// * weatherDensity(weatherData) * 3.0;

	return densityAlongCone;
}

// ray marches clouds
fixed4 Raymarch(float3 rayOrigin, float3 rayDirection, float stepSize, float steps, float cosAngle)
{
	float3 pos = rayOrigin;
	fixed4 res = 0.0; // cloud color
	float lod = 0.0;

	float3 stepVec = rayDirection * stepSize;

	int sampleCount = steps;

	float density                   = 0.0;
	float cloud_test                = 0.0;
	int zero_density_sample_count   = 0;
	
	for (int i = 0; i < sampleCount; i++)
	{
		if (res.a >= 0.99) { // check if is behind some geometrical object or that cloud color aplha is almost 1
			break;  // if it is then raymarch ends
		}
	
		// sample weather
		float3 weatherData = GetWeatherData(pos);
		float heightFraction = GetHeightFractionForPoint(pos);
	
		if (weatherData.r <= 0.1)
		{
			pos += stepVec;
			zero_density_sample_count ++;
			continue;
		}

		if (cloud_test > 0.0)
		{
			float sampled_density = SampleCloudDensity(pos, heightFraction, weatherData, lod, false);
			if (sampled_density == 0.0)
			{
				zero_density_sample_count++;
			}

			if (zero_density_sample_count != 6)
			{
				density += sampled_density;

				if (sampled_density != 0.0)
				{
					float4 particle = sampled_density; // construct cloud particle

					float densityAlongCone = SampleCloudDensityAlongCone(pos, lod, _SunDir);
					
					float totalEnergy = CalculateLightEnergy(densityAlongCone, cosAngle, sampled_density);
					float3 directLight = _SunColor * totalEnergy;

					float3 ambientLight = lerp(_CloudBaseColor, _CloudTopColor, heightFraction); // and ambient

					directLight *= _SunLightFactor; // multiply them by their uniform factors
					ambientLight *= _AmbientLightFactor;

					particle.rgb = directLight + ambientLight; // add lights up and set cloud particle color

					particle.rgb *= particle.a; // multiply color by clouds density
					res = (1.0 - res.a) * particle + res; // use premultiplied alpha blending to acumulate samples
				}

				pos += stepVec;
			}else
			{
				cloud_test = 0.0;
				zero_density_sample_count = 0;
			}
		}else
		{
			cloud_test = SampleCloudDensity(pos, heightFraction, weatherData, lod, true);
			if(cloud_test == 0.0){
				pos += stepVec;
			}
		}
	}
	
	return res;
}

#endif