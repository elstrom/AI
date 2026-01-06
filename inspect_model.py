#!/usr/bin/env python3
"""
Script untuk inspect ONNX model secara detail
"""

import onnx
import onnxruntime as ort
import numpy as np
from onnx import numpy_helper

def inspect_onnx_model(model_path):
    """Inspect ONNX model structure"""
    print(f"{'='*80}")
    print(f"INSPECTING MODEL: {model_path}")
    print(f"{'='*80}\n")
    
    # Load model
    model = onnx.load(model_path)
    
    # Basic info
    print("=" * 80)
    print("BASIC INFO")
    print("=" * 80)
    print(f"IR Version: {model.ir_version}")
    print(f"Producer: {model.producer_name}")
    print(f"Producer Version: {model.producer_version}")
    print(f"Domain: {model.domain}")
    print(f"Model Version: {model.model_version}")
    print(f"Doc String: {model.doc_string}")
    
    # Graph info
    graph = model.graph
    print(f"\nGraph Name: {graph.name}")
    print(f"Number of nodes: {len(graph.node)}")
    print(f"Number of initializers: {len(graph.initializer)}")
    
    # Inputs
    print("\n" + "=" * 80)
    print("INPUTS")
    print("=" * 80)
    for i, input_tensor in enumerate(graph.input):
        print(f"\nInput {i}: {input_tensor.name}")
        print(f"  Type: {input_tensor.type.tensor_type.elem_type}")
        shape = [d.dim_value if d.dim_value > 0 else d.dim_param for d in input_tensor.type.tensor_type.shape.dim]
        print(f"  Shape: {shape}")
    
    # Outputs
    print("\n" + "=" * 80)
    print("OUTPUTS")
    print("=" * 80)
    for i, output_tensor in enumerate(graph.output):
        print(f"\nOutput {i}: {output_tensor.name}")
        print(f"  Type: {output_tensor.type.tensor_type.elem_type}")
        shape = [d.dim_value if d.dim_value > 0 else d.dim_param for d in output_tensor.type.tensor_type.shape.dim]
        print(f"  Shape: {shape}")
    
    # Metadata
    print("\n" + "=" * 80)
    print("METADATA")
    print("=" * 80)
    for meta in model.metadata_props:
        print(f"{meta.key}: {meta.value}")
    
    # First few nodes
    print("\n" + "=" * 80)
    print("FIRST 10 NODES")
    print("=" * 80)
    for i, node in enumerate(graph.node[:10]):
        print(f"\nNode {i}: {node.op_type}")
        print(f"  Name: {node.name}")
        print(f"  Inputs: {node.input}")
        print(f"  Outputs: {node.output}")
        if node.attribute:
            print(f"  Attributes:")
            for attr in node.attribute:
                print(f"    {attr.name}: {attr}")
    
    # Last few nodes
    print("\n" + "=" * 80)
    print("LAST 10 NODES")
    print("=" * 80)
    for i, node in enumerate(graph.node[-10:]):
        print(f"\nNode {len(graph.node)-10+i}: {node.op_type}")
        print(f"  Name: {node.name}")
        print(f"  Inputs: {node.input}")
        print(f"  Outputs: {node.output}")
    
    # Check for NMS or post-processing nodes
    print("\n" + "=" * 80)
    print("SPECIAL NODES (NMS, Slice, Concat, etc)")
    print("=" * 80)
    special_ops = ['NonMaxSuppression', 'Slice', 'Concat', 'Reshape', 'Transpose', 'Sigmoid', 'Softmax']
    for node in graph.node:
        if node.op_type in special_ops:
            print(f"\n{node.op_type}: {node.name}")
            print(f"  Inputs: {node.input}")
            print(f"  Outputs: {node.output}")

def test_model_with_dummy_input(model_path):
    """Test model with dummy input"""
    print("\n" + "=" * 80)
    print("TESTING WITH DUMMY INPUT")
    print("=" * 80)
    
    session = ort.InferenceSession(model_path)
    
    # Get input details
    input_name = session.get_inputs()[0].name
    input_shape = session.get_inputs()[0].shape
    
    # Create dummy input (all zeros)
    print(f"\nCreating dummy input: {input_name} with shape {input_shape}")
    dummy_input = np.zeros((1, 3, 640, 640), dtype=np.float32)
    print(f"Dummy input: shape={dummy_input.shape}, dtype={dummy_input.dtype}, range=[{dummy_input.min()}, {dummy_input.max()}]")
    
    # Run inference
    print("\nRunning inference with ZEROS...")
    outputs = session.run(None, {input_name: dummy_input})
    
    print(f"\nGot {len(outputs)} outputs:")
    for i, out in enumerate(outputs):
        print(f"Output {i}:")
        print(f"  Shape: {out.shape}")
        print(f"  Dtype: {out.dtype}")
        print(f"  Range: [{out.min():.6f}, {out.max():.6f}]")
        print(f"  Mean: {out.mean():.6f}")
        print(f"  Std: {out.std():.6f}")
        print(f"  Non-zero elements: {np.count_nonzero(out)}")
    
    # Try with random input
    print("\n" + "-" * 80)
    print("Testing with RANDOM input...")
    random_input = np.random.rand(1, 3, 640, 640).astype(np.float32)
    print(f"Random input: shape={random_input.shape}, dtype={random_input.dtype}, range=[{random_input.min():.3f}, {random_input.max():.3f}]")
    
    outputs = session.run(None, {input_name: random_input})
    
    print(f"\nGot {len(outputs)} outputs:")
    for i, out in enumerate(outputs):
        print(f"Output {i}:")
        print(f"  Shape: {out.shape}")
        print(f"  Dtype: {out.dtype}")
        print(f"  Range: [{out.min():.6f}, {out.max():.6f}]")
        print(f"  Mean: {out.mean():.6f}")
        print(f"  Std: {out.std():.6f}")
        print(f"  Non-zero elements: {np.count_nonzero(out)}")
        
        # Show some sample values
        if out.size < 100:
            print(f"  Values: {out.flatten()[:20]}")

def check_model_opset(model_path):
    """Check model opset versions"""
    print("\n" + "=" * 80)
    print("OPSET VERSIONS")
    print("=" * 80)
    
    model = onnx.load(model_path)
    
    for opset in model.opset_import:
        print(f"Domain: {opset.domain if opset.domain else 'ai.onnx'}")
        print(f"Version: {opset.version}")

if __name__ == "__main__":
    model_path = "Model_train/best.onnx"
    
    # Inspect model structure
    inspect_onnx_model(model_path)
    
    # Check opset
    check_model_opset(model_path)
    
    # Test with dummy inputs
    test_model_with_dummy_input(model_path)
