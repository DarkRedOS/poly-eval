#!/bin/bash
set -e

echo "=========================================="
echo "Polyglot Benchmark Runner"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Default values
CONFIG_FILE=""
API_URL=""
API_KEY=""
MODEL_NAME=""
EDIT_FORMAT="whole"
THREADS=10
TRIES=2
LANGUAGE=""
EXERCISES_DIR=""

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Run Polyglot benchmark for multi-language code generation evaluation.

Options:
  --config, -c FILE          JSON config file with all settings
  --api-url, -u URL          API base URL (e.g., https://api.example.com/v1)
  --api-key, -k KEY          API key for authentication
  --model, -m MODEL          Model name (e.g., gpt-4o, claude-3-sonnet)
  --edit-format FORMAT       Edit format (whole, diff, udiff) [default: whole]
  --threads, -t NUM          Number of parallel threads [default: 10]
  --tries NUM                Number of tries per exercise [default: 2]
  --language, -l LANG        Specific language to test (e.g., python, rust)
  --exercises-dir DIR        Custom exercises directory
  --help, -h                 Show this help message

Examples:
  # Using config file
  $0 --config config.json

  # Using CLI arguments
  $0 --api-url https://api.example.com/v1 --api-key sk-xxx --model gpt-4o

  # Test specific language
  $0 --config config.json --language python

Config file format (config.json):
{
  "api_url": "https://api.example.com/v1",
  "api_key": "your-api-key",
  "model": "gpt-4o",
  "edit_format": "whole",
  "threads": 10,
  "tries": 2
}

Platform Notes:
  - macOS: Ensure Docker Desktop is running
  - Linux: Docker daemon must be active
  - VM recommended for production runs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --api-url|-u)
            API_URL="$2"
            shift 2
            ;;
        --api-key|-k)
            API_KEY="$2"
            shift 2
            ;;
        --model|-m)
            MODEL_NAME="$2"
            shift 2
            ;;
        --edit-format)
            EDIT_FORMAT="$2"
            shift 2
            ;;
        --threads|-t)
            THREADS="$2"
            shift 2
            ;;
        --tries)
            TRIES="$2"
            shift 2
            ;;
        --language|-l)
            LANGUAGE="$2"
            shift 2
            ;;
        --exercises-dir)
            EXERCISES_DIR="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Load from config file if provided
if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    print_info "Loading configuration from: $CONFIG_FILE"
    
    CONFIG_JSON=$(cat "$CONFIG_FILE")
    
    [ -z "$API_URL" ] && API_URL=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('api_url', ''))" 2>/dev/null || true)
    [ -z "$API_KEY" ] && API_KEY=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('api_key', ''))" 2>/dev/null || true)
    [ -z "$MODEL_NAME" ] && MODEL_NAME=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('model', ''))" 2>/dev/null || true)
    [ "$EDIT_FORMAT" = "whole" ] && EDIT_FORMAT=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('edit_format', 'whole'))" 2>/dev/null || echo "whole")
    [ "$THREADS" = "10" ] && THREADS=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('threads', 10))" 2>/dev/null || echo "10")
    [ "$TRIES" = "2" ] && TRIES=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tries', 2))" 2>/dev/null || echo "2")
fi

# Validate required arguments
if [ -z "$API_URL" ]; then
    print_error "API URL is required. Use --api-url or config file."
    exit 1
fi

if [ -z "$API_KEY" ]; then
    print_error "API key is required. Use --api-key or config file."
    exit 1
fi

if [ -z "$MODEL_NAME" ]; then
    print_error "Model name is required. Use --model or config file."
    exit 1
fi

# Paths
AIDER_DIR="${SCRIPT_DIR}/aider-repo"
WORK_DIR="${SCRIPT_DIR}/polyglot-work"
RESULTS_DIR="${SCRIPT_DIR}/results"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Check if aider-benchmark image exists
print_info "Checking for aider-benchmark Docker image..."
if ! docker images --format '{{.Repository}}' | grep -q "^aider-benchmark$"; then
    print_error "aider-benchmark Docker image not found!"
    echo "Please run './setup.sh' first to build the image."
    exit 1
fi

# Check if polyglot-benchmark exists
POLYGLOT_BENCHMARK_DIR="${AIDER_DIR}/tmp.benchmarks/polyglot-benchmark"
if [ ! -d "${POLYGLOT_BENCHMARK_DIR}" ]; then
    print_error "Polyglot benchmark not found at ${POLYGLOT_BENCHMARK_DIR}"
    echo "Please run './setup.sh' first to clone the repositories."
    exit 1
fi

# Set exercises directory
if [ -z "$EXERCISES_DIR" ]; then
    EXERCISES_DIR="/benchmarks/polyglot-benchmark"
fi

# Generate run name
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MODEL_SAFE=$(echo "$MODEL_NAME" | tr '/' '_')
RUN_NAME="${TIMESTAMP}--${MODEL_SAFE}-${EDIT_FORMAT}"

# Display configuration
echo ""
echo "=========================================="
echo "Configuration"
echo "=========================================="
echo "API URL: $API_URL"
echo "Model: $MODEL_NAME"
echo "Edit Format: $EDIT_FORMAT"
echo "Threads: $THREADS"
echo "Tries: $TRIES"
echo "Run Name: $RUN_NAME"
echo "Results Dir: ${RESULTS_DIR}"
if [ -n "$LANGUAGE" ]; then
    echo "Language Filter: $LANGUAGE"
fi
echo "=========================================="
echo ""

# Create work directory for this run
RUN_WORK_DIR="${WORK_DIR}/${RUN_NAME}"
mkdir -p "${RUN_WORK_DIR}"

# Copy polyglot-benchmark to work directory
print_info "Copying polyglot-benchmark to work directory..."
cp -r "${POLYGLOT_BENCHMARK_DIR}" "${RUN_WORK_DIR}/polyglot-benchmark"

# Build model name for aider (add openai/ prefix if needed for LiteLLM)
if [[ ! "$MODEL_NAME" =~ ^openai/ ]] && [[ ! "$MODEL_NAME" =~ ^anthropic/ ]] && [[ ! "$MODEL_NAME" =~ ^claude/ ]]; then
    AIDER_MODEL="openai/${MODEL_NAME}"
else
    AIDER_MODEL="$MODEL_NAME"
fi

# Build the benchmark command
BENCH_CMD="./benchmark/benchmark.py ${RUN_NAME} --model ${AIDER_MODEL} --edit-format ${EDIT_FORMAT} --threads ${THREADS} --tries ${TRIES} --exercises-dir ${EXERCISES_DIR}"

if [ -n "$LANGUAGE" ]; then
    BENCH_CMD="${BENCH_CMD} --language ${LANGUAGE}"
fi

# Run the benchmark
print_info "Starting Polyglot benchmark..."
print_info "Command: $BENCH_CMD"
echo ""

docker run --rm \
    --memory=12g \
    --memory-swap=12g \
    --add-host=host.docker.internal:host-gateway \
    -v "${RUN_WORK_DIR}/polyglot-benchmark:/benchmarks/polyglot-benchmark" \
    -v "${AIDER_DIR}:/aider" \
    -e "OPENAI_API_KEY=${API_KEY}" \
    -e "OPENAI_API_BASE=${API_URL}" \
    -e "AIDER_DOCKER=1" \
    -e "AIDER_BENCHMARK_DIR=/benchmarks" \
    -w "/aider" \
    aider-benchmark \
    bash -c "pip install -e .[dev] 2>/dev/null && ${BENCH_CMD}" 2>&1 | tee "${RESULTS_DIR}/${RUN_NAME}_output.txt"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    print_success "Benchmark completed successfully!"
    
    # Copy results from aider's tmp.benchmarks to our results directory
    print_info "Collecting results..."
    if [ -d "${AIDER_DIR}/tmp.benchmarks/${RUN_NAME}" ]; then
        cp -r "${AIDER_DIR}/tmp.benchmarks/${RUN_NAME}" "${RESULTS_DIR}/"
        print_success "Results copied to ${RESULTS_DIR}/${RUN_NAME}"
        
        # Parse results and generate standardized result.json
        print_info "Generating standardized result.json..."
        
        STATS_FILE="${RESULTS_DIR}/${RUN_NAME}/stats.yaml"
        if [ -f "$STATS_FILE" ]; then
            python3 << PYEOF
import json
import yaml
import os

try:
    with open("${RESULTS_DIR}/${RUN_NAME}/stats.yaml", "r") as f:
        stats = yaml.safe_load(f)
    
    # Extract metrics
    total = stats.get("num_exercises", 0)
    passed = stats.get("pass_count", 0)
    failed = total - passed if total > 0 else 0
    pass_rate = (passed / total * 100) if total > 0 else 0.0
    
    result = {
        "metrics": {
            "main": {
                "name": "pass@1",
                "value": round(pass_rate / 100, 4)
            },
            "secondary": {
                "success_rate": round(pass_rate, 2),
                "failure_rate": round(100 - pass_rate, 2)
            },
            "additional": {
                "total_tasks": total,
                "successful_tasks": passed,
                "failed_tasks": failed,
                "edit_format": "${EDIT_FORMAT}",
                "model": "${MODEL_NAME}",
                "run_name": "${RUN_NAME}",
                "pass_count": passed,
                "fail_count": failed
            }
        }
    }
    
    with open("${RESULTS_DIR}/result.json", "w") as f:
        json.dump(result, f, indent=2)
    
    print(f"[INFO] Generated result.json with pass_rate: {pass_rate:.2f}%")
    
except Exception as e:
    print(f"[WARNING] Could not parse stats.yaml: {e}")
    # Generate a basic result.json
    result = {
        "metrics": {
            "main": {"name": "pass@1", "value": 0.0},
            "secondary": {"success_rate": 0.0, "failure_rate": 100.0},
            "additional": {
                "total_tasks": 0,
                "successful_tasks": 0,
                "failed_tasks": 0,
                "error": str(e)
            }
        }
    }
    with open("${RESULTS_DIR}/result.json", "w") as f:
        json.dump(result, f, indent=2)
PYEOF
            print_success "Result saved to ${RESULTS_DIR}/result.json"
        fi
        
        # Display stats if available
        echo ""
        echo "=========================================="
        echo "Benchmark Statistics"
        echo "=========================================="
        if [ -f "$STATS_FILE" ]; then
            cat "$STATS_FILE"
        fi
        echo "=========================================="
    else
        print_warning "Results directory not found at ${AIDER_DIR}/tmp.benchmarks/${RUN_NAME}"
    fi
    
    print_success "Log saved to: ${RESULTS_DIR}/${RUN_NAME}_output.txt"
else
    print_error "Benchmark failed with exit code $EXIT_CODE"
    print_info "Partial log saved to: ${RESULTS_DIR}/${RUN_NAME}_output.txt"
    exit $EXIT_CODE
fi

# Cleanup work directory
echo ""
print_info "Cleaning up..."
rm -rf "${RUN_WORK_DIR}/polyglot-benchmark"

echo ""
echo "=========================================="
print_success "All done!"
echo "=========================================="
echo "Results saved to: ${RESULTS_DIR}"
