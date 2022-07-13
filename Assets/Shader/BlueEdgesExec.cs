using System;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways, ExecuteInEditMode]
public class BlueEdgesExec : MonoBehaviour
{
    public ComputeShader theCS;
    public Texture refImg;
    RenderTexture rt;
    CommandBuffer cmd;
    int computeIdx;
    public int radius = 1;
    
    void Start()
    {
        cmd = new CommandBuffer();

        if (theCS != null && refImg != null)
        {
            rt = new RenderTexture(refImg.width, refImg.height, 0, RenderTextureFormat.ARGBHalf);
            rt.enableRandomWrite = true;
            rt.filterMode = FilterMode.Point;
            rt.Create();
            
            computeIdx = theCS.FindKernel("CSMain");
        }
    }

    private void Update()
    {
        if (theCS && refImg && rt)
        {
            cmd.SetComputeIntParam(theCS, "_Width", refImg.width);
            cmd.SetComputeIntParam(theCS, "_Height", refImg.height);
            cmd.SetComputeIntParam(theCS, "_Radius", radius);

            cmd.SetComputeTextureParam(theCS, computeIdx, "Input", refImg);
            cmd.SetComputeTextureParam(theCS, computeIdx, "Output", rt);

            cmd.DispatchCompute(theCS, computeIdx,
                (refImg.width + 8 - 1) / 8,
                (refImg.height + 8 - 1) / 8,
                1
            );

            Graphics.ExecuteCommandBuffer(cmd);

            //GetComponent<Renderer>().material.SetTexture("_UnlitColorMap", rt);
        }
    }
}
