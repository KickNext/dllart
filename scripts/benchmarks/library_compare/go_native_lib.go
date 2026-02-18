package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"
)

const cpuMask int64 = 0x7fffffff
const ioBlockSize = 1 << 20

var ioPayload []byte

func setError(errorOut **C.char, message string) {
	if errorOut == nil {
		return
	}
	*errorOut = C.CString(message)
}

func clearError(errorOut **C.char) {
	if errorOut == nil {
		return
	}
	*errorOut = nil
}

func fillBuffer(buffer []byte) {
	seed := uint32(0xA5A5A5A5)
	for i := range buffer {
		seed ^= seed << 13
		seed ^= seed >> 17
		seed ^= seed << 5
		buffer[i] = byte(seed & 0xff)
	}
}

//export bench_init
func bench_init(runtimePath *C.char, errorOut **C.char) C.int {
	_ = runtimePath
	clearError(errorOut)
	return 0
}

//export bench_cpu_work
func bench_cpu_work(iterations C.int64_t, seed C.int64_t, checksumOut *C.int64_t, errorOut **C.char) C.int {
	clearError(errorOut)
	if iterations <= 0 {
		setError(errorOut, "iterations must be > 0")
		return 1
	}
	if checksumOut == nil {
		setError(errorOut, "checksum_out is null")
		return 1
	}

	x := int64(seed) & cpuMask
	acc := int64(0)
	for i := int64(0); i < int64(iterations); i++ {
		x = (x*1103515245 + 12345) & cpuMask
		acc = (acc + ((x ^ i) & cpuMask)) & cpuMask
	}
	*checksumOut = C.int64_t(acc)
	return 0
}

//export bench_io_write
func bench_io_write(path *C.char, fileMB C.int64_t, bytesWrittenOut *C.int64_t, errorOut **C.char) C.int {
	clearError(errorOut)
	if path == nil {
		setError(errorOut, "path must be non-empty")
		return 1
	}
	if fileMB <= 0 {
		setError(errorOut, "file_mb must be > 0")
		return 1
	}
	if bytesWrittenOut == nil {
		setError(errorOut, "bytes_written_out is null")
		return 1
	}

	if C.GoString(path) == "" {
		setError(errorOut, "path must be non-empty")
		return 1
	}

	totalBytes := int64(fileMB) * 1024 * 1024
	if totalBytes <= 0 {
		setError(errorOut, "computed total bytes must be > 0")
		return 1
	}

	pattern := make([]byte, ioBlockSize)
	fillBuffer(pattern)

	out := make([]byte, int(totalBytes))
	offset := int64(0)
	for offset < totalBytes {
		chunk := int64(len(pattern))
		if totalBytes-offset < chunk {
			chunk = totalBytes - offset
		}
		copy(out[int(offset):int(offset+chunk)], pattern[:int(chunk)])
		offset += chunk
	}

	ioPayload = out
	*bytesWrittenOut = C.int64_t(totalBytes)
	return 0
}

//export bench_io_read
func bench_io_read(path *C.char, fileMB C.int64_t, checksumOut *C.int64_t, errorOut **C.char) C.int {
	clearError(errorOut)
	if path == nil {
		setError(errorOut, "path must be non-empty")
		return 1
	}
	if fileMB <= 0 {
		setError(errorOut, "file_mb must be > 0")
		return 1
	}
	if checksumOut == nil {
		setError(errorOut, "checksum_out is null")
		return 1
	}

	if C.GoString(path) == "" {
		setError(errorOut, "path must be non-empty")
		return 1
	}

	totalBytes := int64(fileMB) * 1024 * 1024
	if totalBytes <= 0 {
		setError(errorOut, "computed total bytes must be > 0")
		return 1
	}
	if int64(len(ioPayload)) != totalBytes {
		setError(errorOut, "payload size mismatch")
		return 1
	}

	checksum := int64(0)
	for _, b := range ioPayload {
		checksum += int64(b)
	}

	ioPayload = nil
	*checksumOut = C.int64_t(checksum)
	return 0
}

//export bench_shutdown
func bench_shutdown() {}

//export bench_string_free
func bench_string_free(value *C.char) {
	if value == nil {
		return
	}
	C.free(unsafe.Pointer(value))
}

func main() {
}
