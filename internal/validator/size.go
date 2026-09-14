package validator

import (
	"github.com/meimolihan/fan-reubah/internal/constants"
	"github.com/meimolihan/fan-reubah/pkg/errors"
)

func ValidateFileSize(size int64) error {
	if size > constants.MaxFileSize {
		return errors.New(
			errors.ErrInvalidSize,
			"File size exceeds maximum allowed size (32MB)",
			nil,
		)
	}
	return nil
}

func ValidateImageDimensions(width, height int) error {
	if width > constants.MaxImageWidth || height > constants.MaxImageHeight {
		return errors.New(
			errors.ErrInvalidSize,
			"Image dimensions exceed maximum allowed size (8192x8192)",
			nil,
		)
	}
	return nil
} 