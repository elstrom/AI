package preprocessor

import (
	"image"
	"image/color"
	"math"
	"go_server/internal/logging"
	"github.com/sirupsen/logrus"
)

type FramePreprocessor struct {
	logger *logging.Logger
}

func NewFramePreprocessor(logger *logging.Logger) *FramePreprocessor {
	return &FramePreprocessor{
		logger: logger,
	}
}

// ProcessFrame processes the frame before sending to Python AI system
func (p *FramePreprocessor) ProcessFrame(frameData []byte, width, height int) ([]byte, error) {
	p.logger.WithFields(logrus.Fields{
		"width":  width,
		"height": height,
		"size":   len(frameData),
	}).Debug("Processing frame")
	
	// Convert byte data to image
	img, err := p.bytesToImage(frameData, width, height)
	if err != nil {
		p.logger.WithField("error", err).Error("Failed to convert bytes to image")
		return nil, err
	}
	
	// Resize image if needed (example: resize to 224x224 for model input)
	resizedImg := p.resizeImage(img, 224, 224)
	
	// Normalize image
	normalizedImg := p.normalizeImage(resizedImg)
	
	// Convert back to bytes
	processedData, err := p.imageToBytes(normalizedImg)
	if err != nil {
		p.logger.WithField("error", err).Error("Failed to convert image to bytes")
		return nil, err
	}
	
	p.logger.WithFields(logrus.Fields{
		"original_size": len(frameData),
		"processed_size": len(processedData),
	}).Debug("Frame processed successfully")
	
	return processedData, nil
}

// bytesToImage converts byte data to image.Image
func (p *FramePreprocessor) bytesToImage(data []byte, width, height int) (image.Image, error) {
	// This is a simplified implementation
	// In a real scenario, you would need to decode the image based on its format (JPEG, PNG, etc.)
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	
	// Assuming data is in RGBA format
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			idx := (y*width + x) * 4
			if idx+3 < len(data) {
				r := data[idx]
				g := data[idx+1]
				b := data[idx+2]
				a := data[idx+3]
				img.Set(x, y, color.RGBA{r, g, b, a})
			}
		}
	}
	
	return img, nil
}

// resizeImage resizes the image to the specified dimensions
func (p *FramePreprocessor) resizeImage(img image.Image, width, height int) image.Image {
	// This is a simplified implementation
	// In a real scenario, you would use a proper image resizing library
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	
	srcBounds := img.Bounds()
	srcW := srcBounds.Dx()
	srcH := srcBounds.Dy()
	
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			srcX := x * srcW / width
			srcY := y * srcH / height
			dst.Set(x, y, img.At(srcX, srcY))
		}
	}
	
	return dst
}

// normalizeImage normalizes the image pixel values
func (p *FramePreprocessor) normalizeImage(img image.Image) image.Image {
	bounds := img.Bounds()
	normalized := image.NewRGBA(bounds)
	
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, a := img.At(x, y).RGBA()
			
			// Normalize to 0-1 range
			nr := float64(r) / 65535.0
			ng := float64(g) / 65535.0
			nb := float64(b) / 65535.0
			na := float64(a) / 65535.0
			
			// Convert back to 0-255 range
			nr = math.Round(nr * 255)
			ng = math.Round(ng * 255)
			nb = math.Round(nb * 255)
			na = math.Round(na * 255)
			
			normalized.Set(x, y, color.RGBA{
				R: uint8(nr),
				G: uint8(ng),
				B: uint8(nb),
				A: uint8(na),
			})
		}
	}
	
	return normalized
}

// imageToBytes converts image.Image to byte array
func (p *FramePreprocessor) imageToBytes(img image.Image) ([]byte, error) {
	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()
	
	data := make([]byte, width*height*4)
	
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			r, g, b, a := img.At(x, y).RGBA()
			
			idx := (y*width + x) * 4
			data[idx] = uint8(r >> 8)
			data[idx+1] = uint8(g >> 8)
			data[idx+2] = uint8(b >> 8)
			data[idx+3] = uint8(a >> 8)
		}
	}
	
	return data, nil
}