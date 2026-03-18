#!/bin/bash
set -e

echo "=========================================="
echo "Polyglot Benchmark Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Function to print colored output
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

# Detect OS
OS_TYPE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
        OS_TYPE="debian"
        print_info "Detected Ubuntu/Debian system"
    elif [ "$ID" = "centos" ] || [ "$ID" = "rhel" ] || [ "$ID" = "fedora" ]; then
        OS_TYPE="redhat"
        print_info "Detected CentOS/RHEL/Fedora system"
    else
        OS_TYPE="linux-other"
        print_warning "Non-Debian/RedHat Linux detected."
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    print_info "Detected macOS system"
else
    OS_TYPE="unknown"
    print_warning "Cannot detect OS. Will attempt to continue."
fi

# Check if Docker is installed and running
print_info "Checking Docker..."
if ! command -v docker &> /dev/null; then
    print_warning "Docker is not installed."
    
    case "$OS_TYPE" in
        debian)
            print_info "Installing Docker on Ubuntu/Debian..."
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker.io
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        redhat)
            print_info "Installing Docker on CentOS/RHEL/Fedora..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y docker
            else
                sudo yum install -y docker
            fi
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        macos)
            print_error "Docker is not installed."
            print_info "On macOS, please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
            print_info "Or use: brew install --cask docker"
            exit 1
            ;;
        *)
            print_error "Unsupported OS for automatic Docker installation."
            print_info "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    print_warning "Docker daemon is not running. Attempting to start..."
    
    case "$OS_TYPE" in
        debian|redhat)
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || {
                print_error "Failed to start Docker daemon. Please start it manually."
                exit 1
            }
            ;;
        macos)
            print_error "Docker daemon is not running."
            print_info "Please start Docker Desktop manually and re-run this script."
            exit 1
            ;;
        *)
            print_error "Cannot start Docker automatically on this OS."
            print_info "Please start Docker manually and re-run this script."
            exit 1
            ;;
    esac
fi

print_success "Docker is available"

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_info "Installing git..."
    case "$OS_TYPE" in
        debian)
            sudo apt-get update -qq && sudo apt-get install -y -qq git
            ;;
        redhat)
            if command -v dnf &> /dev/null; then
                sudo dnf install -y git
            else
                sudo yum install -y git
            fi
            ;;
        macos)
            print_error "git is not installed."
            print_info "Please install Xcode Command Line Tools: xcode-select --install"
            exit 1
            ;;
        *)
            print_error "git is not installed. Please install it manually."
            exit 1
            ;;
    esac
fi

print_success "Git found"

# Create work directory
WORK_DIR="${SCRIPT_DIR}/polyglot-work"
mkdir -p "${WORK_DIR}"

# Step 1: Clone Aider repository
AIDER_DIR="${SCRIPT_DIR}/aider-repo"
if [ -d "${AIDER_DIR}" ]; then
    print_info "Aider repository already exists at ${AIDER_DIR}"
    print_info "Updating repository..."
    cd "${AIDER_DIR}" && git pull --quiet || {
        print_warning "Git pull failed, re-cloning..."
        rm -rf "${AIDER_DIR}"
        git clone --quiet https://github.com/Aider-AI/aider.git "${AIDER_DIR}"
    }
else
    print_info "Cloning Aider repository..."
    git clone --quiet https://github.com/Aider-AI/aider.git "${AIDER_DIR}"
fi
cd "${SCRIPT_DIR}"

# Step 2: Create benchmarks directory
BENCHMARKS_DIR="${AIDER_DIR}/tmp.benchmarks"
mkdir -p "${BENCHMARKS_DIR}"

# Step 3: Clone polyglot-benchmark repository
POLYGLOT_BENCHMARK_DIR="${BENCHMARKS_DIR}/polyglot-benchmark"
if [ -d "${POLYGLOT_BENCHMARK_DIR}" ]; then
    print_info "Polyglot benchmark already exists at ${POLYGLOT_BENCHMARK_DIR}"
    print_info "Updating repository..."
    cd "${POLYGLOT_BENCHMARK_DIR}" && git pull --quiet || {
        print_warning "Git pull failed, re-cloning..."
        rm -rf "${POLYGLOT_BENCHMARK_DIR}"
        git clone --quiet https://github.com/Aider-AI/polyglot-benchmark "${POLYGLOT_BENCHMARK_DIR}"
    }
else
    print_info "Cloning polyglot-benchmark repository..."
    git clone --quiet https://github.com/Aider-AI/polyglot-benchmark "${POLYGLOT_BENCHMARK_DIR}"
fi
cd "${SCRIPT_DIR}"

# Step 4: Build aider-benchmark Docker image
print_info "Checking for aider-benchmark Docker image..."
if docker images --format '{{.Repository}}' | grep -q "^aider-benchmark$"; then
    print_success "aider-benchmark Docker image already exists"
else
    print_info "Building aider-benchmark Docker image..."
    print_warning "This may take several minutes (10-15 mins on first run)..."
    cd "${AIDER_DIR}"
    
    # Try building with setuptools-scm version override
    export SETUPTOOLS_SCM_PRETEND_VERSION="0.86.2.dev"
    
    if [ -f "benchmark/docker_build.sh" ]; then
        chmod +x benchmark/docker_build.sh
        if ./benchmark/docker_build.sh 2>&1; then
            print_success "Docker image built successfully"
        else
            print_warning "Standard build failed, trying alternative approach..."
            docker build \
                --file benchmark/Dockerfile \
                --build-arg SETUPTOOLS_SCM_PRETEND_VERSION=0.86.2.dev \
                -t aider-benchmark \
                . 2>&1 || {
                print_error "Failed to build aider-benchmark image"
                exit 1
            }
        fi
    else
        print_error "benchmark/docker_build.sh not found"
        exit 1
    fi
fi
cd "${SCRIPT_DIR}"

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"
print_success "Results directory created: ${RESULTS_DIR}"

echo ""
echo "=========================================="
print_success "Setup Complete!"
echo "=========================================="
echo "Aider repository: ${AIDER_DIR}"
echo "Polyglot benchmark: ${POLYGLOT_BENCHMARK_DIR}"
echo "Docker image: aider-benchmark"
echo "Results: ${RESULTS_DIR}"
echo ""
echo "Platform Notes:"
echo "  - macOS: Ensure Docker Desktop is running"
echo "  - Linux: Docker daemon must be active"
echo "  - VM recommended for production runs"
echo ""
echo "Next steps:"
echo "  1. Run: ./run.sh --api-url <url> --api-key <key> --model <model>"
echo ""
