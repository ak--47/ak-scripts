#!/bin/bash

# Convert SVG files to PNG with specified dimensions
svg_to_png() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: svg_to_png <svg_file> [dimensions] [output_file]"
        echo ""
        echo "Convert SVG files to PNG with specified dimensions using ImageMagick."
        echo ""
        echo "Arguments:"
        echo "  svg_file      Path to the SVG file to convert"
        echo "  dimensions    Output dimensions in WIDTHxHEIGHT format (default: 3024x1960)"
        echo "  output_file   Output PNG file path (default: same name with .png extension)"
        echo ""
        echo "Examples:"
        echo "  svg_to_png logo.svg"
        echo "  svg_to_png logo.svg 1920x1080"
        echo "  svg_to_png logo.svg 800x600 /path/to/output.png"
        echo "  svg_to_png assets/*.svg 2048x1536  # Batch convert"
        return 0
    fi

    # Check if ImageMagick is available
    if ! command -v convert &> /dev/null; then
        echo "❌ Error: ImageMagick 'convert' command is not installed or not in PATH"
        echo "Install with: brew install imagemagick (macOS) or apt-get install imagemagick (Ubuntu)"
        return 1
    fi

    local input_svg="$1"
    local dimensions="${2:-3024x1960}"
    local output_png="${3:-}"

    # Handle wildcard patterns for batch processing
    if [[ "$input_svg" == *"*"* ]]; then
        echo "🔄 Batch processing SVG files matching: $input_svg"
        echo "Dimensions: $dimensions"
        echo ""

        local count=0
        local success=0
        local failed=0

        for svg_file in $input_svg; do
            if [[ -f "$svg_file" ]]; then
                ((count++))
                local base_name=$(basename "$svg_file" .svg)
                local dir_name=$(dirname "$svg_file")
                local batch_output="${dir_name}/${base_name}.png"

                echo "[$count] Converting: $(basename "$svg_file")"

                if convert -resize "$dimensions" "$svg_file" "$batch_output" 2>/dev/null; then
                    echo "    ✅ Created: $batch_output"
                    ((success++))
                else
                    echo "    ❌ Failed: $(basename "$svg_file")"
                    ((failed++))
                fi
            fi
        done

        echo ""
        echo "📊 Batch conversion complete:"
        echo "   ✅ Successful: $success"
        if [[ $failed -gt 0 ]]; then
            echo "   ❌ Failed: $failed"
        fi
        echo ""
        return 0
    fi

    # Single file processing
    if [[ ! -f "$input_svg" ]]; then
        echo "❌ Error: SVG file '$input_svg' not found"
        return 1
    fi

    # Validate SVG file
    if [[ ! "$input_svg" =~ \.svg$ ]]; then
        echo "❌ Error: File '$input_svg' does not have .svg extension"
        return 1
    fi

    # Determine output filename
    if [[ -z "$output_png" ]]; then
        output_png="${input_svg%.svg}.png"
    fi

    # Validate dimensions format
    if [[ ! "$dimensions" =~ ^[0-9]+x[0-9]+$ ]]; then
        echo "❌ Error: Dimensions must be in WIDTHxHEIGHT format (e.g., 1920x1080)"
        return 1
    fi

    echo "🔄 Converting SVG to PNG"
    echo "Input:      $input_svg"
    echo "Output:     $output_png"
    echo "Dimensions: $dimensions"
    echo ""

    # Check if output file already exists
    if [[ -f "$output_png" ]]; then
        echo "⚠️  Output file already exists: $output_png"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Conversion cancelled"
            return 1
        fi
    fi

    # Perform the conversion
    echo "🚀 Converting..."
    if convert -resize "$dimensions" "$input_svg" "$output_png" 2>/dev/null; then
        echo "✅ Conversion complete: $output_png"

        # Show file size info
        if command -v ls &> /dev/null; then
            local input_size=$(ls -lh "$input_svg" | awk '{print $5}')
            local output_size=$(ls -lh "$output_png" | awk '{print $5}')
            echo ""
            echo "📊 File sizes:"
            echo "   SVG: $input_size"
            echo "   PNG: $output_size"
        fi

        echo ""
        return 0
    else
        echo "❌ Conversion failed. Please check:"
        echo "   - SVG file is valid"
        echo "   - ImageMagick is properly installed"
        echo "   - You have write permissions in the output directory"
        return 1
    fi
}

# Export function
export -f svg_to_png

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    svg_to_png "$@"
fi