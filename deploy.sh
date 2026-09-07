#!/bin/bash
# UrgentSee Deployment Script
# Usage: ./deploy.sh [target]
# Targets: worker, ios, all (default)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prereqs() {
  log_info "Checking prerequisites..."
  
  # Check for Node.js
  if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please install Node.js >= 18"
    exit 1
  fi
  
  # Check for wrangler
  if ! command -v wrangler &> /dev/null; then
    log_error "Wrangler is not installed. Install with: npm install -g wrangler"
    exit 1
  fi
  
  # Check for Xcode command line tools (for iOS build)
  if ! command -v xcodebuild &> /dev/null; then
    log_warn "xcodebuild not found. iOS builds will be skipped."
  fi
  
  log_info "Prerequisites check passed"
}

# Deploy Cloudflare Worker
deploy_worker() {
  log_info "Deploying Cloudflare Worker..."
  
  cd urgentsee-edge
  
  # Install dependencies
  if [ ! -d "node_modules" ]; then
    log_info "Installing Node.js dependencies..."
    npm install
  fi
  
  # Deploy to Cloudflare
  log_info "Deploying to Cloudflare Workers..."
  wrangler deploy
  
  cd ..
  log_info "Cloudflare Worker deployed successfully"
}

# Build iOS app
build_ios() {
  log_info "Building iOS app..."
  
  # Check if we're in the right directory
  if [ ! -d "UrgentSee" ]; then
    log_error "UrgentSee directory not found. Please run from project root."
    exit 1
  }
  
  # Check for Xcode
  if ! command -v xcodebuild &> /dev/null; then
    log_error "xcodebuild not found. Please install Xcode command line tools."
    exit 1
  }
  
  # Clean and build
  log_info "Cleaning build..."
  xcodebuild clean -workspace UrgentSee.xcworkspace -scheme UrgentSee -configuration Release || \
    xcodebuild clean -project UrgentSee.xcodeproj -scheme UrgentSee -configuration Release
  
  log_info "Building iOS app..."
  xcodebuild archive \
    -workspace UrgentSee.xcworkspace \
    -scheme UrgentSee \
    -configuration Release \
    -archivePath build/UrgentSee.xcarchive \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  
  log_info "iOS app built successfully at build/UrgentSee.xcarchive"
}

# Run tests
run_tests() {
  log_info "Running tests..."
  
  # Run Swift tests
  if [ -d "UrgentSee" ]; then
    log_info "Running Swift unit tests..."
    xcodebuild test -workspace UrgentSee.xcworkspace -scheme UrgentSee -destination 'platform=iOS Simulator,name=iPhone 14,OS=latest' || \
      log_warn "Some Swift tests failed or no test target found"
  fi
  
  # Run TypeScript tests
  if [ -d "urgentsee-edge" ]; then
    log_info "Running TypeScript tests..."
    cd urgentsee-edge
    if [ -f "package.json" ] && grep -q "test" package.json; then
      npm test
    else
      log_warn "No test script found in package.json"
    fi
    cd ..
  fi
  
  log_info "Tests completed"
}

# Main deployment logic
main() {
  local target="${1:-all}"
  
  check_prereqs
  
  case "$target" in
    worker)
      deploy_worker
      ;;
    ios)
      build_ios
      ;;
    test)
      run_tests
      ;;
    all|*)
      deploy_worker
      build_ios
      run_tests
      ;;
  esac
  
  log_info "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"