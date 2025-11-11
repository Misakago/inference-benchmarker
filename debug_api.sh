#!/bin/bash

# GPUStack API Diagnostic Script
# This script tests the API endpoint to diagnose issues with empty choices

API_URL="http://localhost:8001"
API_KEY="gpustack_d521a91e37db5823_542fb6d87249361f5133216132800e4e"
MODEL="qwen3-vl-8b-instruct"

echo "=========================================="
echo "GPUStack API Diagnostic Tool"
echo "=========================================="
echo ""

# Test 1: Check if API is accessible
echo "Test 1: Checking API accessibility..."
if curl -s --max-time 5 "${API_URL}/health" > /dev/null 2>&1 || curl -s --max-time 5 "${API_URL}/v1/models" > /dev/null 2>&1; then
    echo "✓ API is accessible"
else
    echo "✗ Cannot reach API at ${API_URL}"
    echo "  Please ensure GPUStack is running"
    exit 1
fi
echo ""

# Test 2: List available models
echo "Test 2: Listing available models..."
curl -s "${API_URL}/v1/models" \
    -H "Authorization: Bearer ${API_KEY}" | jq -r '.data[]?.id // empty' 2>/dev/null | head -10
if [ $? -ne 0 ]; then
    echo "  (jq not available, showing raw response)"
    curl -s "${API_URL}/v1/models" -H "Authorization: Bearer ${API_KEY}"
fi
echo ""

# Test 3: Simple non-streaming request
echo "Test 3: Testing non-streaming chat completion..."
echo "Request payload:"
cat << 'EOF'
{
  "model": "qwen3-vl-8b-instruct",
  "messages": [{"role": "user", "content": "Hello"}],
  "max_tokens": 50,
  "stream": false
}
EOF

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": "Hello"}],
        "max_tokens": 50,
        "stream": false
    }')

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo ""
echo "Response (HTTP ${HTTP_CODE}):"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo ""

# Check choices array
CHOICES_COUNT=$(echo "$BODY" | jq '.choices | length' 2>/dev/null)
if [ "$CHOICES_COUNT" = "0" ] || [ -z "$CHOICES_COUNT" ]; then
    echo "✗ PROBLEM: choices array is empty or missing!"
    echo ""
    echo "Possible causes:"
    echo "1. Model name mismatch - check available models above"
    echo "2. Qwen3-VL requires special message format (multimodal)"
    echo "3. API endpoint incompatibility"
    echo ""
else
    echo "✓ Choices array has ${CHOICES_COUNT} item(s)"
fi

# Test 4: Streaming request
echo "=========================================="
echo "Test 4: Testing streaming chat completion..."
echo "Request payload:"
cat << 'EOF'
{
  "model": "qwen3-vl-8b-instruct",
  "messages": [{"role": "user", "content": "Say hello"}],
  "max_tokens": 50,
  "stream": true
}
EOF
echo ""
echo "Streaming response (first 10 events):"

curl -s -N "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": "Say hello"}],
        "max_tokens": 50,
        "stream": true
    }' | head -20

echo ""
echo "=========================================="
echo "Test 5: Testing with text-only content..."
# For VL models, sometimes we need to specify content differently
curl -s -N "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": [{"type": "text", "text": "Hello"}]}],
        "max_tokens": 50,
        "stream": true
    }' | head -20

echo ""
echo "=========================================="
echo "Diagnostic complete!"
echo ""
echo "Next steps:"
echo "1. Check if model name in 'Test 2' matches your model"
echo "2. If choices is empty in 'Test 3', try the alternative format in 'Test 5'"
echo "3. Check if streaming responses in 'Test 4' or 'Test 5' contain valid choices"
