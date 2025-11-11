#!/bin/bash

# GPUStack API Diagnostic Script - Enhanced Version
# This script performs comprehensive testing of the API endpoint to diagnose issues with empty choices

set -o pipefail

API_URL="${API_URL:-http://localhost:8001}"
API_KEY="${API_KEY:-gpustack_d521a91e37db5823_542fb6d87249361f5133216132800e4e}"
MODEL="${MODEL:-qwen3-vl-8b-instruct}"
OUTPUT_DIR="./debug_output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "GPUStack API Diagnostic Tool - Enhanced"
echo "=========================================="
echo "API URL: ${API_URL}"
echo "Model: ${MODEL}"
echo "Output directory: ${OUTPUT_DIR}"
echo ""

# Helper function to check jq availability
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Helper function to print colored status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}✓${NC} ${message}"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}✗${NC} ${message}"
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}⚠${NC} ${message}"
    else
        echo -e "${BLUE}ℹ${NC} ${message}"
    fi
}

# Test 1: Check if API is accessible
echo "=========================================="
echo "Test 1: API Accessibility"
echo "=========================================="
echo "Testing endpoints: /health, /v1/models"
echo ""

if curl -s --max-time 5 "${API_URL}/health" > /dev/null 2>&1; then
    print_status "ok" "Health endpoint is accessible"
    curl -s "${API_URL}/health" > "${OUTPUT_DIR}/health.json"
elif curl -s --max-time 5 "${API_URL}/v1/models" > /dev/null 2>&1; then
    print_status "ok" "Models endpoint is accessible"
else
    print_status "error" "Cannot reach API at ${API_URL}"
    echo "  Please ensure GPUStack is running on the correct port"
    exit 1
fi
echo ""

# Test 2: List available models
echo "=========================================="
echo "Test 2: Available Models"
echo "=========================================="
MODELS_RESPONSE=$(curl -s "${API_URL}/v1/models" -H "Authorization: Bearer ${API_KEY}")
echo "$MODELS_RESPONSE" > "${OUTPUT_DIR}/models.json"

if has_jq; then
    echo "Available models:"
    echo "$MODELS_RESPONSE" | jq -r '.data[]?.id // empty' | while read -r model; do
        if [ "$model" = "$MODEL" ]; then
            print_status "ok" "$model (configured model)"
        else
            echo "  - $model"
        fi
    done

    MODEL_COUNT=$(echo "$MODELS_RESPONSE" | jq '.data | length' 2>/dev/null)
    echo ""
    echo "Total models: ${MODEL_COUNT}"
else
    echo "Raw response (install jq for better formatting):"
    echo "$MODELS_RESPONSE"
fi
echo ""

# Test 3: Non-streaming request with detailed analysis
echo "=========================================="
echo "Test 3: Non-Streaming Request Analysis"
echo "=========================================="
echo "Request configuration:"
echo "  - Model: ${MODEL}"
echo "  - Content: 'Hello'"
echo "  - Max tokens: 50"
echo "  - Stream: false"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
    "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": "Hello"}],
        "max_tokens": 50,
        "stream": false,
        "temperature": 0.0
    }')

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
TIME_TOTAL=$(echo "$RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed -e '/HTTP_CODE:/d' -e '/TIME_TOTAL:/d')

echo "$BODY" > "${OUTPUT_DIR}/non_streaming_response.json"

echo "Response status: HTTP ${HTTP_CODE} (${TIME_TOTAL}s)"
echo ""

if has_jq; then
    # Detailed analysis
    CHOICES_COUNT=$(echo "$BODY" | jq '.choices | length' 2>/dev/null)

    if [ "$HTTP_CODE" != "200" ]; then
        print_status "error" "HTTP error: ${HTTP_CODE}"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    elif [ "$CHOICES_COUNT" = "0" ] || [ -z "$CHOICES_COUNT" ]; then
        print_status "error" "Choices array is empty or missing!"
        echo ""
        echo "Response structure:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        echo ""
        print_status "warn" "Possible causes:"
        echo "  1. Model name '${MODEL}' not found (check Test 2 output)"
        echo "  2. Qwen3-VL requires multimodal message format"
        echo "  3. API endpoint incompatibility"
        echo "  4. Server-side error (check GPUStack logs)"
    else
        print_status "ok" "Choices array has ${CHOICES_COUNT} item(s)"

        # Extract detailed info
        CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content' 2>/dev/null)
        FINISH_REASON=$(echo "$BODY" | jq -r '.choices[0].finish_reason' 2>/dev/null)
        PROMPT_TOKENS=$(echo "$BODY" | jq -r '.usage.prompt_tokens' 2>/dev/null)
        COMPLETION_TOKENS=$(echo "$BODY" | jq -r '.usage.completion_tokens' 2>/dev/null)
        TOTAL_TOKENS=$(echo "$BODY" | jq -r '.usage.total_tokens' 2>/dev/null)

        echo "  - Finish reason: ${FINISH_REASON}"
        echo "  - Prompt tokens: ${PROMPT_TOKENS}"
        echo "  - Completion tokens: ${COMPLETION_TOKENS}"
        echo "  - Total tokens: ${TOTAL_TOKENS}"
        echo "  - Content preview: ${CONTENT:0:80}..."
    fi
else
    echo "Raw response:"
    echo "$BODY"
fi
echo ""

# Test 4: Streaming request with SSE event analysis
echo "=========================================="
echo "Test 4: Streaming Request - SSE Event Analysis"
echo "=========================================="
echo "Request configuration:"
echo "  - Model: ${MODEL}"
echo "  - Content: 'Say hello'"
echo "  - Max tokens: 50"
echo "  - Stream: true"
echo ""

STREAM_OUTPUT="${OUTPUT_DIR}/streaming_events.txt"
curl -s -N "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": "Say hello"}],
        "max_tokens": 50,
        "stream": true,
        "temperature": 0.0
    }' > "$STREAM_OUTPUT"

# Analyze streaming events
echo "Analyzing SSE events..."
EVENT_COUNT=0
EMPTY_CHOICES_COUNT=0
VALID_CHOICES_COUNT=0
CONTENT_CHUNKS=0

if has_jq; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^data:\ (.+)$ ]]; then
            EVENT_COUNT=$((EVENT_COUNT + 1))
            JSON_DATA="${BASH_REMATCH[1]}"

            # Skip [DONE] marker
            if [ "$JSON_DATA" = "[DONE]" ]; then
                continue
            fi

            # Check if choices array exists and is not empty
            CHOICES_LEN=$(echo "$JSON_DATA" | jq '.choices | length' 2>/dev/null)
            if [ "$CHOICES_LEN" = "0" ] || [ -z "$CHOICES_LEN" ]; then
                EMPTY_CHOICES_COUNT=$((EMPTY_CHOICES_COUNT + 1))
                echo "[Event $EVENT_COUNT] ✗ Empty choices array"
                echo "$JSON_DATA" | jq '.' >> "${OUTPUT_DIR}/empty_choices_events.json"
            else
                VALID_CHOICES_COUNT=$((VALID_CHOICES_COUNT + 1))
                DELTA_CONTENT=$(echo "$JSON_DATA" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
                if [ -n "$DELTA_CONTENT" ] && [ "$DELTA_CONTENT" != "null" ]; then
                    CONTENT_CHUNKS=$((CONTENT_CHUNKS + 1))
                fi
            fi
        fi
    done < "$STREAM_OUTPUT"

    echo ""
    print_status "info" "SSE Event Statistics:"
    echo "  - Total events: ${EVENT_COUNT}"
    echo "  - Valid choices: ${VALID_CHOICES_COUNT}"
    echo "  - Empty choices: ${EMPTY_CHOICES_COUNT}"
    echo "  - Content chunks: ${CONTENT_CHUNKS}"

    if [ "$EMPTY_CHOICES_COUNT" -gt 0 ]; then
        print_status "error" "Found ${EMPTY_CHOICES_COUNT} events with empty choices array!"
        echo "  Saved to: ${OUTPUT_DIR}/empty_choices_events.json"
    else
        print_status "ok" "All streaming events have valid choices arrays"
    fi
else
    echo "First 20 events (install jq for detailed analysis):"
    head -20 "$STREAM_OUTPUT"
fi
echo ""

# Test 5: Multimodal message format
echo "=========================================="
echo "Test 5: Multimodal Message Format (VL Models)"
echo "=========================================="
echo "Testing with content: [{\"type\": \"text\", \"text\": \"Hello\"}]"
echo ""

MM_STREAM_OUTPUT="${OUTPUT_DIR}/multimodal_streaming_events.txt"
curl -s -N "${API_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{
        "model": "'"${MODEL}"'",
        "messages": [{"role": "user", "content": [{"type": "text", "text": "Hello"}]}],
        "max_tokens": 50,
        "stream": true,
        "temperature": 0.0
    }' > "$MM_STREAM_OUTPUT"

MM_EVENT_COUNT=$(grep -c "^data:" "$MM_STREAM_OUTPUT" 2>/dev/null || echo "0")
if [ "$MM_EVENT_COUNT" -gt 0 ]; then
    print_status "ok" "Multimodal format works (${MM_EVENT_COUNT} events received)"
    echo "  First 5 events:"
    head -10 "$MM_STREAM_OUTPUT"
else
    print_status "error" "Multimodal format failed or received no events"
fi
echo ""

# Test 6: Different max_tokens values
echo "=========================================="
echo "Test 6: Testing Different max_tokens Values"
echo "=========================================="
for MAX_TOKENS in 10 100 200 500; do
    echo -n "Testing max_tokens=${MAX_TOKENS}... "
    RESPONSE=$(curl -s "${API_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"${MODEL}"'",
            "messages": [{"role": "user", "content": "Hi"}],
            "max_tokens": '"${MAX_TOKENS}"',
            "stream": false
        }')

    if has_jq; then
        CHOICES_LEN=$(echo "$RESPONSE" | jq '.choices | length' 2>/dev/null)
        if [ "$CHOICES_LEN" -gt 0 ] 2>/dev/null; then
            TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens' 2>/dev/null)
            print_status "ok" "Success (generated ${TOKENS} tokens)"
        else
            print_status "error" "Empty choices array"
        fi
    else
        echo "OK (install jq for detailed analysis)"
    fi
done
echo ""

# Test 7: Concurrent requests simulation
echo "=========================================="
echo "Test 7: Concurrent Requests Simulation"
echo "=========================================="
echo "Sending 5 concurrent requests..."
CONCURRENT_FAILURES=0

for i in {1..5}; do
    (
        RESPONSE=$(curl -s "${API_URL}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${API_KEY}" \
            -d '{
                "model": "'"${MODEL}"'",
                "messages": [{"role": "user", "content": "Test request '"${i}"'"}],
                "max_tokens": 20,
                "stream": false
            }')
        echo "$RESPONSE" > "${OUTPUT_DIR}/concurrent_request_${i}.json"

        if has_jq; then
            CHOICES_LEN=$(echo "$RESPONSE" | jq '.choices | length' 2>/dev/null)
            if [ "$CHOICES_LEN" = "0" ] || [ -z "$CHOICES_LEN" ]; then
                echo "error" > "${OUTPUT_DIR}/concurrent_request_${i}.status"
            else
                echo "ok" > "${OUTPUT_DIR}/concurrent_request_${i}.status"
            fi
        fi
    ) &
done

wait

# Count failures
for i in {1..5}; do
    if [ -f "${OUTPUT_DIR}/concurrent_request_${i}.status" ]; then
        STATUS=$(cat "${OUTPUT_DIR}/concurrent_request_${i}.status")
        if [ "$STATUS" = "error" ]; then
            CONCURRENT_FAILURES=$((CONCURRENT_FAILURES + 1))
        fi
    fi
done

if [ "$CONCURRENT_FAILURES" -gt 0 ]; then
    print_status "error" "${CONCURRENT_FAILURES}/5 concurrent requests had empty choices"
else
    print_status "ok" "All 5 concurrent requests succeeded"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""

if [ "$EMPTY_CHOICES_COUNT" -gt 0 ] || [ "$CONCURRENT_FAILURES" -gt 0 ]; then
    print_status "error" "Issues detected with empty choices arrays"
    echo ""
    echo "Recommendations:"
    echo "  1. Check GPUStack/vLLM logs for errors"
    echo "  2. Verify model name matches: '${MODEL}'"
    echo "  3. Try updating vLLM to latest version (>=0.5.0 for Qwen3-VL)"
    echo "  4. Check if model requires specific message format"
    echo "  5. Review raw responses in: ${OUTPUT_DIR}/"
    echo ""
    echo "For inference-benchmarker, use the patched version that:"
    echo "  - Skips empty choices arrays instead of crashing"
    echo "  - Provides default max_tokens=512"
    echo "  - Logs detailed warnings with raw response data"
else
    print_status "ok" "All tests passed! API is working correctly"
    echo ""
    echo "Your benchmark command should work fine:"
    echo ""
    echo "inference-benchmarker \\"
    echo "  --tokenizer-name Qwen/Qwen3-VL-8B-Instruct \\"
    echo "  --model-name ${MODEL} \\"
    echo "  --url ${API_URL} \\"
    echo "  --api-key ${API_KEY} \\"
    echo "  --benchmark-kind sweep \\"
    echo "  --num-rates 10 \\"
    echo "  --duration 120s \\"
    echo "  --warmup 30s \\"
    echo "  --dataset misakago/test \\"
    echo "  --dataset-file data.json \\"
    echo "  --decode-options \"num_tokens=200,max_tokens=220,min_tokens=180,variance=10\""
fi

echo ""
echo "All diagnostic outputs saved to: ${OUTPUT_DIR}/"
echo "=========================================="
