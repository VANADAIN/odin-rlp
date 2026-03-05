package rlp

// RLP decoding (inverse of encoding).
//
// Decodes a byte stream into an Item tree.
// Allocates memory for Bytes and List values.

// Decode a complete RLP-encoded byte stream into an Item.
decode :: proc(data: []u8, allocator := context.allocator) -> (item: Item, err: Error) {
	if len(data) == 0 do return nil, .Unexpected_End
	result, consumed, decode_err := _decode_item(data, allocator)
	if decode_err != .None do return nil, decode_err
	if consumed != len(data) {
		item_destroy(&result, allocator)
		return nil, .Invalid_Input
	}
	return result, .None
}

// Decode and return remaining unconsumed bytes (for streaming).
decode_with_rest :: proc(data: []u8, allocator := context.allocator) -> (item: Item, rest: []u8, err: Error) {
	if len(data) == 0 do return nil, nil, .Unexpected_End
	result, consumed, decode_err := _decode_item(data, allocator)
	if decode_err != .None do return nil, nil, decode_err
	return result, data[consumed:], .None
}

// --- Internal decoding ---

_decode_item :: proc(data: []u8, allocator := context.allocator) -> (item: Item, consumed: int, err: Error) {
	if len(data) == 0 do return nil, 0, .Unexpected_End

	prefix := data[0]

	if prefix < 0x80 {
		// Single byte
		buf, alloc_err := make([]u8, 1, allocator)
		if alloc_err != nil do return nil, 0, .Alloc_Failed
		buf[0] = prefix
		return Item(Bytes(buf)), 1, .None
	}

	if prefix <= 0xb7 {
		// Short string (0-55 bytes)
		str_len := int(prefix - 0x80)
		if len(data) < 1 + str_len do return nil, 0, .Unexpected_End

		// Canonical check: single byte < 0x80 should not use this form
		if str_len == 1 && data[1] < 0x80 do return nil, 0, .Non_Canonical

		buf, alloc_err := make([]u8, str_len, allocator)
		if alloc_err != nil do return nil, 0, .Alloc_Failed
		copy(buf, data[1:1 + str_len])
		return Item(Bytes(buf)), 1 + str_len, .None
	}

	if prefix <= 0xbf {
		// Long string (>55 bytes)
		len_of_len := int(prefix - 0xb7)
		if len(data) < 1 + len_of_len do return nil, 0, .Unexpected_End

		// Canonical check: length of length must not have leading zeros
		if data[1] == 0 do return nil, 0, .Non_Canonical

		str_len := _read_uint(data[1:1 + len_of_len])

		// Canonical check: value must actually require long form
		if str_len <= 55 do return nil, 0, .Non_Canonical

		total := 1 + len_of_len + str_len
		if len(data) < total do return nil, 0, .Unexpected_End

		buf, alloc_err := make([]u8, str_len, allocator)
		if alloc_err != nil do return nil, 0, .Alloc_Failed
		copy(buf, data[1 + len_of_len:total])
		return Item(Bytes(buf)), total, .None
	}

	if prefix <= 0xf7 {
		// Short list (0-55 bytes payload)
		payload_len := int(prefix - 0xc0)
		if len(data) < 1 + payload_len do return nil, 0, .Unexpected_End
		items, list_err := _decode_list_payload(data[1:1 + payload_len], allocator)
		if list_err != .None do return nil, 0, list_err
		return Item(List(items)), 1 + payload_len, .None
	}

	// Long list (>55 bytes payload)
	len_of_len := int(prefix - 0xf7)
	if len(data) < 1 + len_of_len do return nil, 0, .Unexpected_End

	// Canonical check: length of length must not have leading zeros
	if data[1] == 0 do return nil, 0, .Non_Canonical

	payload_len := _read_uint(data[1:1 + len_of_len])

	// Canonical check: value must actually require long form
	if payload_len <= 55 do return nil, 0, .Non_Canonical

	total := 1 + len_of_len + payload_len
	if len(data) < total do return nil, 0, .Unexpected_End

	items, list_err := _decode_list_payload(data[1 + len_of_len:total], allocator)
	if list_err != .None do return nil, 0, list_err
	return Item(List(items)), total, .None
}

_decode_list_payload :: proc(payload: []u8, allocator := context.allocator) -> (items: []Item, err: Error) {
	// First pass: count items
	count := 0
	offset := 0
	for offset < len(payload) {
		_, consumed, skip_err := _skip_item(payload[offset:])
		if skip_err != .None do return nil, skip_err
		offset += consumed
		count += 1
	}

	result, alloc_err := make([]Item, count, allocator)
	if alloc_err != nil do return nil, .Alloc_Failed

	// Second pass: decode items
	offset = 0
	for i in 0 ..< count {
		item, consumed, decode_err := _decode_item(payload[offset:], allocator)
		if decode_err != .None {
			for j in 0 ..< i {
				item_destroy(&result[j], allocator)
			}
			delete(result, allocator)
			return nil, decode_err
		}
		result[i] = item
		offset += consumed
	}

	return result, .None
}

// Skip over an item without decoding it, returning bytes consumed.
_skip_item :: proc(data: []u8) -> (item_type: u8, consumed: int, err: Error) {
	if len(data) == 0 do return 0, 0, .Unexpected_End

	prefix := data[0]

	if prefix < 0x80 {
		return prefix, 1, .None
	}
	if prefix <= 0xb7 {
		str_len := int(prefix - 0x80)
		if len(data) < 1 + str_len do return 0, 0, .Unexpected_End
		return prefix, 1 + str_len, .None
	}
	if prefix <= 0xbf {
		len_of_len := int(prefix - 0xb7)
		if len(data) < 1 + len_of_len do return 0, 0, .Unexpected_End
		str_len := _read_uint(data[1:1 + len_of_len])
		total := 1 + len_of_len + str_len
		if len(data) < total do return 0, 0, .Unexpected_End
		return prefix, total, .None
	}
	if prefix <= 0xf7 {
		payload_len := int(prefix - 0xc0)
		if len(data) < 1 + payload_len do return 0, 0, .Unexpected_End
		return prefix, 1 + payload_len, .None
	}

	len_of_len := int(prefix - 0xf7)
	if len(data) < 1 + len_of_len do return 0, 0, .Unexpected_End
	payload_len := _read_uint(data[1:1 + len_of_len])
	total := 1 + len_of_len + payload_len
	if len(data) < total do return 0, 0, .Unexpected_End
	return prefix, total, .None
}

// Read a big-endian unsigned integer from bytes.
_read_uint :: proc(data: []u8) -> int {
	result := 0
	for b in data {
		result = result << 8 | int(b)
	}
	return result
}
