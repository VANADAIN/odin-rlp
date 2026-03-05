package rlp

import "core:math/big"

// RLP encoding per Ethereum specification.
//
// Rules:
//   - Single byte in [0x00, 0x7f]: encoded as itself
//   - String 0-55 bytes: 0x80+len prefix, then string
//   - String >55 bytes: 0xb7+len_of_len prefix, then length, then string
//   - List 0-55 bytes payload: 0xc0+len prefix, then concatenated items
//   - List >55 bytes payload: 0xf7+len_of_len prefix, then length, then items

// Encode an RLP item into a newly allocated byte slice.
encode :: proc(item: Item, allocator := context.allocator) -> (result: []u8, err: Error) {
	size := encoded_size(item)
	buf, alloc_err := make([]u8, size, allocator)
	if alloc_err != nil do return nil, .Alloc_Failed
	n, write_err := encode_to_buf(item, buf)
	if write_err != .None {
		delete(buf, allocator)
		return nil, write_err
	}
	return buf[:n], .None
}

// Encode an RLP item into an existing buffer. Returns bytes written.
encode_to_buf :: proc(item: Item, buf: []u8) -> (n: int, err: Error) {
	switch v in item {
	case Bytes:
		return _encode_bytes(transmute([]u8)v, buf)
	case List:
		return _encode_list(transmute([]Item)v, buf)
	}
	return 0, .Invalid_Input
}

// Calculate the encoded size of an item without allocating.
encoded_size :: proc(item: Item) -> int {
	switch v in item {
	case Bytes:
		return _bytes_encoded_size(transmute([]u8)v)
	case List:
		return _list_encoded_size(transmute([]Item)v)
	}
	return 0
}

// --- Convenience encoders ---

// Encode a raw byte slice as an RLP string.
encode_bytes :: proc(data: []u8, allocator := context.allocator) -> ([]u8, Error) {
	item := Item(Bytes(data))
	return encode(item, allocator)
}

// Encode a u64 as an RLP string (big-endian, no leading zeros).
encode_uint :: proc(val: u64, allocator := context.allocator) -> ([]u8, Error) {
	if val == 0 {
		item := Item(Bytes(nil))
		return encode(item, allocator)
	}
	be := _uint_to_big_endian(val)
	item := Item(Bytes(be.buf[:be.len]))
	return encode(item, allocator)
}

// Encode a big.Int as an RLP string (big-endian, no leading zeros).
encode_big_int :: proc(val: ^big.Int, allocator := context.allocator) -> (result: []u8, err: Error) {
	is_z, _ := big.is_zero(val)
	if is_z {
		item := Item(Bytes(nil))
		return encode(item, allocator)
	}

	size, size_err := big.int_to_bytes_size(val)
	if size_err != nil do return nil, .Invalid_Input

	buf, alloc_err := make([]u8, size, allocator)
	if alloc_err != nil do return nil, .Alloc_Failed
	defer delete(buf, allocator)

	if big.int_to_bytes_big(val, buf) != nil do return nil, .Invalid_Input

	// Strip leading zeros
	start := 0
	for start < len(buf) - 1 && buf[start] == 0 {
		start += 1
	}

	item := Item(Bytes(buf[start:]))
	return encode(item, allocator)
}

// Encode a 20-byte address as an RLP string.
encode_address :: proc(addr: [20]u8, allocator := context.allocator) -> ([]u8, Error) {
	a := addr
	item := Item(Bytes(a[:]))
	return encode(item, allocator)
}

// Encode a list of items.
encode_list :: proc(items: []Item, allocator := context.allocator) -> ([]u8, Error) {
	item := Item(List(items))
	return encode(item, allocator)
}

// --- Internal encoding ---

_encode_bytes :: proc(data: []u8, buf: []u8) -> (n: int, err: Error) {
	if len(data) == 1 && data[0] < 0x80 {
		if len(buf) < 1 do return 0, .Buffer_Too_Small
		buf[0] = data[0]
		return 1, .None
	}

	if len(data) <= 55 {
		needed := 1 + len(data)
		if len(buf) < needed do return 0, .Buffer_Too_Small
		buf[0] = u8(0x80 + len(data))
		copy(buf[1:], data)
		return needed, .None
	}

	len_be := _uint_to_big_endian(u64(len(data)))
	needed := 1 + len_be.len + len(data)
	if len(buf) < needed do return 0, .Buffer_Too_Small
	buf[0] = u8(0xb7 + len_be.len)
	copy(buf[1:], len_be.buf[:len_be.len])
	copy(buf[1 + len_be.len:], data)
	return needed, .None
}

_encode_list :: proc(items: []Item, buf: []u8) -> (n: int, err: Error) {
	payload_size := 0
	for item in items {
		payload_size += encoded_size(item)
	}

	if payload_size <= 55 {
		needed := 1 + payload_size
		if len(buf) < needed do return 0, .Buffer_Too_Small
		buf[0] = u8(0xc0 + payload_size)
		offset := 1
		for item in items {
			written, write_err := encode_to_buf(item, buf[offset:])
			if write_err != .None do return 0, write_err
			offset += written
		}
		return needed, .None
	}

	len_be := _uint_to_big_endian(u64(payload_size))
	needed := 1 + len_be.len + payload_size
	if len(buf) < needed do return 0, .Buffer_Too_Small
	buf[0] = u8(0xf7 + len_be.len)
	copy(buf[1:], len_be.buf[:len_be.len])
	offset := 1 + len_be.len
	for item in items {
		written, write_err := encode_to_buf(item, buf[offset:])
		if write_err != .None do return 0, write_err
		offset += written
	}
	return needed, .None
}

_bytes_encoded_size :: proc(data: []u8) -> int {
	if len(data) == 1 && data[0] < 0x80 {
		return 1
	}
	if len(data) <= 55 {
		return 1 + len(data)
	}
	len_be := _uint_to_big_endian(u64(len(data)))
	return 1 + len_be.len + len(data)
}

_list_encoded_size :: proc(items: []Item) -> int {
	payload_size := 0
	for item in items {
		payload_size += encoded_size(item)
	}
	if payload_size <= 55 {
		return 1 + payload_size
	}
	len_be := _uint_to_big_endian(u64(payload_size))
	return 1 + len_be.len + payload_size
}

// Convert a u64 to big-endian bytes (no leading zeros).
Big_Endian_U64 :: struct {
	buf: [8]u8,
	len: int,
}

_uint_to_big_endian :: proc(val: u64) -> Big_Endian_U64 {
	if val == 0 {
		return Big_Endian_U64{len = 0}
	}

	result: Big_Endian_U64
	v := val
	i := 7
	for v > 0 {
		result.buf[i] = u8(v & 0xFF)
		v >>= 8
		i -= 1
	}
	start := i + 1
	result.len = 8 - start
	for j in 0 ..< result.len {
		result.buf[j] = result.buf[start + j]
	}
	return result
}
