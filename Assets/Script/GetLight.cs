    using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class GetLight : MonoBehaviour
{
    public GameObject theLight = null;

    public Vector3 lightPos;
    Renderer curRenderer;
    public Color diffuseColor;

    void Start()
    {
    }

    void Update()
    {
        curRenderer = GetComponent<Renderer>();
        if (curRenderer)
        {
            lightPos = theLight.transform.position;
            Light light = theLight.GetComponent<Light>();
            curRenderer.sharedMaterial.SetVector("_DiffuseAlbedo", diffuseColor);
            curRenderer.sharedMaterial.SetVector("_LightPosWS", lightPos);
            curRenderer.sharedMaterial.SetVector("_LightIntensity", light.intensity * (new Vector4(light.color.r, light.color.g, light.color.b, 1.0f))
                );
        }
    }
}
