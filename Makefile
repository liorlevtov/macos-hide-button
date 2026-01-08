# MinimizeToHide Makefile

# Configuration
PROJECT = MinimizeToHide.xcodeproj
SCHEME = MinimizeToHide
CONFIGURATION = Release
BUILD_DIR = ./build
APP_NAME = MinimizeToHide.app
XCODEBUILD = /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

# Output paths
PRODUCTS_DIR = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)
APP_PATH = $(PRODUCTS_DIR)/$(APP_NAME)

.PHONY: all build clean install open help

# Default target
all: build open

# Build the app
build:
	@echo "Building $(APP_NAME)..."
	@$(XCODEBUILD) -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		clean build \
		| grep -E "(Building|Compiling|Linking|Build succeeded|error:|warning:)" || true
	@echo ""
	@echo "✅ Build complete!"
	@echo "📦 App location: $(APP_PATH)"

# Open the build directory in Finder
open:
	@open $(PRODUCTS_DIR)

# Clean build artifacts
clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "✅ Clean complete!"

# Install to Applications folder
install: build
	@echo "Installing to /Applications..."
	@cp -R "$(APP_PATH)" /Applications/
	@echo "✅ Installed to /Applications/$(APP_NAME)"

# Run the app
run: build
	@echo "Running $(APP_NAME)..."
	@open "$(APP_PATH)"

# Show help
help:
	@echo "MinimizeToHide Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build and open output directory (default)"
	@echo "  build    - Build the app"
	@echo "  open     - Open build directory in Finder"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Build and copy to /Applications"
	@echo "  run      - Build and run the app"
	@echo "  help     - Show this help message"
