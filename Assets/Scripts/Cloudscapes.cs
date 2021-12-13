using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[ExecuteInEditMode]
public class Cloudscapes : MonoBehaviour
{
    public enum RandomJitter
    {
        Off,
        Random,
        BlueNoise
    }
    
    public Material skyMaterial;
    
    [HeaderAttribute("Performance")]
    [Range(1, 256)]
    public int steps = 128;
    public bool adjustDensity = true;
    public AnimationCurve stepDensityAdjustmentCurve = new AnimationCurve(new Keyframe(0.0f, 3.019f), new Keyframe(0.25f, 1.233f), new Keyframe(0.5f, 1.0f), new Keyframe(1.0f, 0.892f));
    [Range(1, 8)]
    public int downSample = 1;
    public Texture2D blueNoiseTexture;
    public RandomJitter randomJitterNoise = RandomJitter.BlueNoise;

    [HeaderAttribute("Cloud modeling")]
    // public Gradient gradientLow;
    // public Gradient gradientMed;
    // public Gradient gradientHigh;
    
    public Texture2D curlNoise;
    public TextAsset lowFreqNoise;
    public TextAsset highFreqNoise;
    public float startHeight = 1500.0f;
    public float thickness = 4000.0f;
    public float planetSize = 35000.0f;
    public Vector3 planetZeroCoordinate = new Vector3(0.0f, 0.0f, 0.0f);
    [Range(0.0f, 1.0f)]
    public float scale = 0.3f;
    [Range(0.0f, 32.0f)]
    public float detailScale = 13.9f;
    [Range(0.0f, 1.0f)]
    public float lowFreqMin = 0.366f;
    [Range(0.0f, 1.0f)]
    public float lowFreqMax = 0.8f;
    [Range(0.0f, 1.0f)]
    public float highFreqModifier = 0.21f;
    [Range(0.0f, 10.0f)]
    public float curlDistortScale = 7.44f;
    [Range(0.0f, 1000.0f)]
    public float curlDistortAmount = 407.0f;
    
    [Range(0.0f, 2.0f)]
    public float coverage = 0.92f;
    [Range(0.0f, 2.0f)]
    public float cloudSampleMultiplier = 1.0f;


    [HeaderAttribute("Weather")] 
    public bool useCustomWeather;
    public Texture2D customWeather;
    
    [Range(0.0f, 2.0f)]
    public float weatherScale = 0.1f;
    
    
    [HeaderAttribute("Lighting")] 
    public Light sunLight;
    public Color cloudBaseColor = new Color32(199, 220, 255, 255);
    public Color cloudTopColor = new Color32(255, 255, 255, 255);
    [Range(0.0f, 1.0f)]
    public float ambientLightFactor = 0.551f;
    [Range(0.0f, 1.5f)]
    public float sunLightFactor = 0.79f;
    public Color highSunColor = new Color32(255, 252, 210, 255);
    public Color lowSunColor = new Color32(255, 174, 0, 255);
    [Range(0.0f, 1.0f)]
    public float henyeyGreensteinGForward = 0.4f;
    [Range(0.0f, 1.0f)]
    public float henyeyGreensteinGBackward = 0.179f;
    [Range(0.0f, 200.0f)]
    public float lightStepLength = 64.0f;
    [Range(0.0f, 1.0f)]
    public float lightConeRadius = 0.4f;
    public bool randomUnitSphere = true;
    [Range(0.0f, 4.0f)]
    public float density = 1.0f;

    [HeaderAttribute("Animation")] 
    public float globalMultiplier = 1.0f;
    public float windSpeed = 15.9f;
    public float windDirection = -22.4f;
    public float coverageWindSpeed = 25.0f;
    public float coverageWindDirection = 5.0f;
    // public float highCloudsWindSpeed = 49.2f;
    // public float highCloudsWindDirection = 77.8f;
    
    private Texture3D _cloudShapeTexture;
    private Texture3D _cloudDetailTexture;
    
    private Vector3 _windOffset;
    private Vector2 _coverageWindOffset;
    // private Vector2 _highCloudsWindOffset;
    private Vector3 _windDirectionVector;
    private float _multipliedWindSpeed;
    
    
    private void Awake()
    {
        if (skyMaterial)
        {
            RenderSettings.skybox = skyMaterial;
        }
    }

    private void Start()
    {
        RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering;
        
        _windOffset = new Vector3(0.0f, 0.0f, 0.0f);
        _coverageWindOffset = new Vector3(0.5f / (weatherScale * 0.00025f), 0.5f / (weatherScale * 0.00025f));
        // _highCloudsWindOffset = new Vector3(1500.0f, -900.0f);
        
    }

    private void OnDestroy()
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
    }

    private void Update()
    {
        // updates wind offsets
        _multipliedWindSpeed = windSpeed * globalMultiplier;
        float angleWind = windDirection * Mathf.Deg2Rad;
        _windDirectionVector = new Vector3(Mathf.Cos(angleWind), -0.25f, Mathf.Sin(angleWind));
        _windOffset += _multipliedWindSpeed * _windDirectionVector * Time.deltaTime;

        float angleCoverage = coverageWindDirection * Mathf.Deg2Rad;
        Vector2 coverageDirecton = new Vector2(Mathf.Cos(angleCoverage), Mathf.Sin(angleCoverage));
        _coverageWindOffset += coverageWindSpeed * globalMultiplier * coverageDirecton * Time.deltaTime;
        
    }
    
    private void OnBeginCameraRendering(ScriptableRenderContext context, Camera camera)
    {

        if (_cloudShapeTexture == null) // if shape texture is missing load it in
        {
            _cloudShapeTexture = TGALoader.load3DFromTGASlices(lowFreqNoise);
        }

        if (_cloudDetailTexture == null) // if detail texture is missing load it in
        {
            _cloudDetailTexture = TGALoader.load3DFromTGASlices(highFreqNoise);
        }
        
        Vector3 cameraPos = camera.transform.position;
        
        float sunLightFactorUpdated = sunLightFactor;
        float ambientLightFactorUpdated = ambientLightFactor;
        float sunAngle = sunLight.transform.eulerAngles.x;
        Color sunColor = highSunColor;
        float henyeyGreensteinGBackwardLerp = henyeyGreensteinGBackward;
        
        
        float noiseScale = 0.00001f + scale * 0.0004f;

        if (sunAngle > 170.0f) // change sunlight color based on sun's height.
        {
            float gradient = Mathf.Max(0.0f, (sunAngle - 330.0f) / 30.0f);
            float gradient2 = gradient * gradient;
            sunLightFactorUpdated *= gradient;
            ambientLightFactorUpdated *= gradient;
            henyeyGreensteinGBackwardLerp *= gradient2 * gradient;
            ambientLightFactorUpdated = Mathf.Max(0.02f, ambientLightFactorUpdated);
            sunColor = Color.Lerp(lowSunColor, highSunColor, gradient2);
        }
        
        // send uniforms to shader
        skyMaterial.SetVector("_SunDir", sunLight.transform ? (-sunLight.transform.forward).normalized : Vector3.up);
        skyMaterial.SetVector("_PlanetCenter", planetZeroCoordinate - new Vector3(0, planetSize, 0));
        skyMaterial.SetVector("_ZeroPoint", planetZeroCoordinate);
        skyMaterial.SetColor("_SunColor", sunColor);
        
        skyMaterial.SetColor("_CloudBaseColor", cloudBaseColor);
        skyMaterial.SetColor("_CloudTopColor", cloudTopColor);
        skyMaterial.SetFloat("_AmbientLightFactor", ambientLightFactorUpdated);
        skyMaterial.SetFloat("_SunLightFactor", sunLightFactorUpdated);
        
        
        skyMaterial.SetTexture("_ShapeTexture", _cloudShapeTexture);
        skyMaterial.SetTexture("_DetailTexture", _cloudDetailTexture);
        skyMaterial.SetTexture("_CurlNoise", curlNoise);
        skyMaterial.SetTexture("_BlueNoise", blueNoiseTexture);
        // skyMaterial.SetVector("_Randomness", new Vector4(Random.value, Random.value, Random.value, Random.value));
        if (useCustomWeather)
        {
            skyMaterial.SetTexture("_WeatherTexture", customWeather);
        }

        skyMaterial.SetFloat("_CurlDistortAmount", 150.0f + curlDistortAmount);
        skyMaterial.SetFloat("_CurlDistortScale", curlDistortScale * noiseScale);

        skyMaterial.SetFloat("_LightConeRadius", lightConeRadius);
        skyMaterial.SetFloat("_LightStepLength", lightStepLength);
        skyMaterial.SetFloat("_SphereSize", planetSize);
        skyMaterial.SetVector("_CloudHeightMinMax", new Vector2(startHeight, startHeight + thickness));
        skyMaterial.SetFloat("_Thickness", thickness);
        skyMaterial.SetFloat("_Scale", noiseScale);
        skyMaterial.SetFloat("_DetailScale", detailScale * noiseScale);
        skyMaterial.SetVector("_LowFreqMinMax", new Vector4(lowFreqMin, lowFreqMax));
        skyMaterial.SetFloat("_HighFreqModifier", highFreqModifier);
        skyMaterial.SetFloat("_WeatherScale", weatherScale * 0.00025f);
        skyMaterial.SetFloat("_Coverage", 1.0f - coverage);
        skyMaterial.SetFloat("_HenyeyGreensteinGForward", henyeyGreensteinGForward);
        skyMaterial.SetFloat("_HenyeyGreensteinGBackward", -henyeyGreensteinGBackwardLerp);
        if (adjustDensity)
        {
            skyMaterial.SetFloat("_SampleMultiplier", cloudSampleMultiplier * stepDensityAdjustmentCurve.Evaluate(steps / 256.0f));
        }
        else
        {
            skyMaterial.SetFloat("_SampleMultiplier", cloudSampleMultiplier);
        } 
        

        skyMaterial.SetFloat("_Density", density);

        skyMaterial.SetFloat("_CloudSpeed", _multipliedWindSpeed);
        skyMaterial.SetVector("_WindDirection", _windDirectionVector);
        skyMaterial.SetVector("_CoverageWindOffset", _coverageWindOffset);
        // skyMaterial.SetVector("_HighCloudsWindOffset", _highCloudsWindOffset);
        
        skyMaterial.SetInt("_Steps", steps);
        
        skyMaterial.SetVector("_CameraWS", cameraPos);
    }
}
