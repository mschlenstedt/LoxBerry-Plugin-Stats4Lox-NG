#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Source: Sarnau https://github.com/sarnau/Inside-The-Loxone-Miniserver
# Adaped for Stats4Lox by Christian Fenzl

import struct
from io import BytesIO
import sys
import zlib

s4ltmp = '/dev/shm/s4ltmp'
try:
	sourcefile = sys.argv[1]
	destfile = sys.argv[2]
except:
	print ('First argument is source file')
	print ('Second argument is destination file')
	sys.exit(1)

with open(sourcefile, 'rb') as f:
	header, = struct.unpack('<L', f.read(4))
	if header == 0xaabbccee:	# magic word to detect a compressed file
		compressedSize,uncompressedSize,checksum, = struct.unpack('<LLL', f.read(12))
		data = f.read(compressedSize)
		index = 0
		resultStr = bytearray()
		while index<len(data):
			# the first byte contains the number of bytes to copy in the upper
			# nibble. If this nibble is 15, then another byte follows with
			# the remainder of bytes to copy. (Comment: it might be possible that
			# it follows the same scheme as below, which means: if more than
			# 255+15 bytes need to be copied, another 0xff byte follows and so on)
			byte, = struct.unpack('<B', data[index:index+1])
			index += 1
			copyBytes = byte >> 4
			byte &= 0xf
			if copyBytes == 15:
				while True:
					addByte = data[index]
					copyBytes += addByte
					index += 1
					if addByte != 0xff:
						break
			if copyBytes > 0:
				resultStr += data[index:index+copyBytes]
				index += copyBytes
			if index >= len(data):
				break
			# Reference to data which already was copied into the result.
			# bytesBack is the offset from the end of the string
			bytesBack, = struct.unpack('<H', data[index:index+2])
			index += 2
			# the number of bytes to be transferred is at least 4 plus the lower
			# nibble of the package header.
			bytesBackCopied = 4 + byte
			if byte == 15:
				# if the header was 15, then more than 19 bytes need to be copied.
				while True:
					val, = struct.unpack('<B', data[index:index+1])
					bytesBackCopied += val
					index += 1
					if val != 0xff:
						break
			# Duplicating the last byte in the buffer multiple times is possible,
			# so we need to account for that.
			while bytesBackCopied > 0:
				if -bytesBack+1 == 0:
					resultStr += resultStr[-bytesBack:]
				else:
					resultStr += resultStr[-bytesBack:-bytesBack+1]
				bytesBackCopied -= 1
		if checksum != zlib.crc32(resultStr):
			print('Checksum is wrong')
			sys.exit(1)
		if len(resultStr) != uncompressedSize:
			print('Uncompressed filesize is wrong %d != %d' % (len(resultStr),uncompressedSize))
			sys.exit(1)
		with open(destfile, "wb") as f:
			f.write(resultStr)
	else:
		print('Could not open file')
		sys.exit(1)
