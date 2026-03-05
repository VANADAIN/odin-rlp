package rlp_tests

import "core:testing"
import "core:encoding/hex"
import rlp "../rlp"

// Helper: decode hex string, then decode RLP, check it matches expected
decode_hex_bytes :: proc(hex_str: string) -> []u8 {
	result, _ := hex.decode(transmute([]u8)hex_str)
	return result
}

// Helper: check decoded item is Bytes with expected content
expect_decoded_bytes :: proc(t: ^testing.T, item: rlp.Item, expected: []u8, msg: string) {
	bytes, is_bytes := item.(rlp.Bytes)
	testing.expect(t, is_bytes, msg)
	if !is_bytes do return
	testing.expect(t, len(bytes) == len(expected), msg)
	for i in 0 ..< len(expected) {
		if bytes[i] != expected[i] {
			testing.expect(t, false, msg)
			return
		}
	}
}

// Helper: check decoded item is a List with expected length
expect_decoded_list :: proc(t: ^testing.T, item: rlp.Item, expected_len: int, msg: string) -> rlp.List {
	list, is_list := item.(rlp.List)
	testing.expect(t, is_list, msg)
	if is_list {
		testing.expect(t, len(list) == expected_len, msg)
	}
	return list
}

// --- Decode single bytes ---

@(test)
test_decode_single_byte :: proc(t: ^testing.T) {
	data := [?]u8{0x05}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode single byte should succeed")
	expected := [?]u8{0x05}
	expect_decoded_bytes(t, item, expected[:], "decoded should be [0x05]")
}

@(test)
test_decode_single_byte_0x00 :: proc(t: ^testing.T) {
	data := [?]u8{0x00}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode 0x00 should succeed")
	expected := [?]u8{0x00}
	expect_decoded_bytes(t, item, expected[:], "decoded should be [0x00]")
}

@(test)
test_decode_single_byte_0x7f :: proc(t: ^testing.T) {
	data := [?]u8{0x7f}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode 0x7f should succeed")
	expected := [?]u8{0x7f}
	expect_decoded_bytes(t, item, expected[:], "decoded should be [0x7f]")
}

// --- Decode empty string ---

@(test)
test_decode_empty_string :: proc(t: ^testing.T) {
	data := [?]u8{0x80}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode empty string should succeed")
	expect_decoded_bytes(t, item, nil, "decoded should be empty bytes")
}

// --- Decode short strings ---

@(test)
test_decode_dog :: proc(t: ^testing.T) {
	data := decode_hex_bytes("83646F67")
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode 'dog' should succeed")
	expect_decoded_bytes(t, item, transmute([]u8)string("dog"), "decoded should be 'dog'")
}

@(test)
test_decode_hello_world :: proc(t: ^testing.T) {
	data := decode_hex_bytes("8B68656C6C6F20776F726C64")
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode 'hello world' should succeed")
	expect_decoded_bytes(t, item, transmute([]u8)string("hello world"), "decoded should be 'hello world'")
}

// --- Decode long strings ---

@(test)
test_decode_lorem_ipsum :: proc(t: ^testing.T) {
	data := decode_hex_bytes(
		"B8384C6F72656D20697073756D20646F6C6F722073697420616D65742C20636F6E7365637465747572206164697069736963696E6720656C6974",
	)
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode lorem ipsum should succeed")

	expected := "Lorem ipsum dolor sit amet, consectetur adipisicing elit"
	expect_decoded_bytes(t, item, transmute([]u8)expected, "decoded should be lorem ipsum")
}

// --- Decode lists ---

@(test)
test_decode_empty_list :: proc(t: ^testing.T) {
	data := [?]u8{0xc0}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode empty list should succeed")
	expect_decoded_list(t, item, 0, "decoded should be empty list")
}

@(test)
test_decode_list_cat_dog :: proc(t: ^testing.T) {
	data := decode_hex_bytes("C88363617483646F67")
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode ['cat','dog'] should succeed")

	list := expect_decoded_list(t, item, 2, "decoded should be list of 2")
	if len(list) == 2 {
		expect_decoded_bytes(t, list[0], transmute([]u8)string("cat"), "first should be 'cat'")
		expect_decoded_bytes(t, list[1], transmute([]u8)string("dog"), "second should be 'dog'")
	}
}

@(test)
test_decode_nested_empty_list :: proc(t: ^testing.T) {
	// [[]]
	data := decode_hex_bytes("C1C0")
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode [[]] should succeed")

	outer := expect_decoded_list(t, item, 1, "outer should be list of 1")
	if len(outer) == 1 {
		expect_decoded_list(t, outer[0], 0, "inner should be empty list")
	}
}

@(test)
test_decode_set_theory_3 :: proc(t: ^testing.T) {
	// [ [], [[]], [ [], [[]] ] ]
	data := decode_hex_bytes("C7C0C1C0C3C0C1C0")
	defer delete(data)
	item, err := rlp.decode(data)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .None, "decode set theory 3 should succeed")

	outer := expect_decoded_list(t, item, 3, "outer should be list of 3")
	if len(outer) == 3 {
		expect_decoded_list(t, outer[0], 0, "first should be []")
		l1 := expect_decoded_list(t, outer[1], 1, "second should be [[]]")
		if len(l1) == 1 {
			expect_decoded_list(t, l1[0], 0, "second inner should be []")
		}
		l2 := expect_decoded_list(t, outer[2], 2, "third should be [[], [[]]]")
		if len(l2) == 2 {
			expect_decoded_list(t, l2[0], 0, "third[0] should be []")
			l2_1 := expect_decoded_list(t, l2[1], 1, "third[1] should be [[]]")
			if len(l2_1) == 1 {
				expect_decoded_list(t, l2_1[0], 0, "third[1][0] should be []")
			}
		}
	}
}

// --- Error cases ---

@(test)
test_decode_empty_input :: proc(t: ^testing.T) {
	item, err := rlp.decode(nil)
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .Unexpected_End, "empty input should return Unexpected_End")
}

@(test)
test_decode_truncated_string :: proc(t: ^testing.T) {
	// Claims 3 bytes but only has 2
	data := [?]u8{0x83, 0x64, 0x6F}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .Unexpected_End, "truncated string should return Unexpected_End")
}

@(test)
test_decode_trailing_bytes :: proc(t: ^testing.T) {
	// Valid encoding of 0x05 followed by extra byte
	data := [?]u8{0x05, 0xFF}
	item, err := rlp.decode(data[:])
	defer rlp.item_destroy(&item)
	testing.expect(t, err == .Invalid_Input, "trailing bytes should return Invalid_Input")
}

// --- Roundtrip tests ---

@(test)
test_roundtrip_empty_string :: proc(t: ^testing.T) {
	item := rlp.Item(rlp.Bytes(nil))
	encoded, err := rlp.encode(item)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode should succeed")

	decoded, derr := rlp.decode(encoded)
	defer rlp.item_destroy(&decoded)
	testing.expect(t, derr == .None, "decode should succeed")
	expect_decoded_bytes(t, decoded, nil, "roundtrip should preserve empty string")
}

@(test)
test_roundtrip_string :: proc(t: ^testing.T) {
	data := transmute([]u8)string("hello world")
	item := rlp.Item(rlp.Bytes(data))
	encoded, err := rlp.encode(item)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode should succeed")

	decoded, derr := rlp.decode(encoded)
	defer rlp.item_destroy(&decoded)
	testing.expect(t, derr == .None, "decode should succeed")
	expect_decoded_bytes(t, decoded, data, "roundtrip should preserve string")
}

@(test)
test_roundtrip_uint :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(1024)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode should succeed")

	decoded, derr := rlp.decode(encoded)
	defer rlp.item_destroy(&decoded)
	testing.expect(t, derr == .None, "decode should succeed")

	bytes, is_bytes := decoded.(rlp.Bytes)
	testing.expect(t, is_bytes, "decoded should be bytes")
	if is_bytes {
		// 1024 = 0x0400
		testing.expect(t, len(bytes) == 2, "1024 should be 2 bytes")
		testing.expect(t, bytes[0] == 0x04, "first byte should be 0x04")
		testing.expect(t, bytes[1] == 0x00, "second byte should be 0x00")
	}
}

@(test)
test_roundtrip_nested_list :: proc(t: ^testing.T) {
	// Encode [ [], [[]] ]
	empty: []rlp.Item
	inner := [?]rlp.Item{rlp.Item(rlp.List(empty))}
	items := [?]rlp.Item{
		rlp.Item(rlp.List(empty)),
		rlp.Item(rlp.List(inner[:])),
	}
	item := rlp.Item(rlp.List(items[:]))

	encoded, err := rlp.encode(item)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode should succeed")

	decoded, derr := rlp.decode(encoded)
	defer rlp.item_destroy(&decoded)
	testing.expect(t, derr == .None, "decode should succeed")

	outer := expect_decoded_list(t, decoded, 2, "outer should be list of 2")
	if len(outer) == 2 {
		expect_decoded_list(t, outer[0], 0, "first should be []")
		l := expect_decoded_list(t, outer[1], 1, "second should be [[]]")
		if len(l) == 1 {
			expect_decoded_list(t, l[0], 0, "inner should be []")
		}
	}
}
