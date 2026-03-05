package rlp_tests

import "core:testing"
import "core:encoding/hex"
import rlp "../rlp"

// Helper: encode and compare to expected hex
expect_encodes_to :: proc(t: ^testing.T, item: rlp.Item, expected_hex: string, msg: string) {
	encoded, err := rlp.encode(item)
	defer delete(encoded)

	testing.expect(t, err == .None, msg)

	got_hex_bytes := hex.encode(encoded)
	defer delete(got_hex_bytes)
	got_hex := string(got_hex_bytes)

	upper_got := to_upper(got_hex)
	defer delete(upper_got)

	testing.expect_value(t, upper_got, expected_hex)
}

// Helper: encode bytes and compare
expect_bytes_encode_to :: proc(t: ^testing.T, data: []u8, expected_hex: string, msg: string) {
	item := rlp.Item(rlp.Bytes(data))
	expect_encodes_to(t, item, expected_hex, msg)
}

to_upper :: proc(s: string) -> string {
	buf := make([]u8, len(s))
	for i in 0 ..< len(s) {
		c := s[i]
		if c >= 'a' && c <= 'f' {
			buf[i] = c - 32
		} else {
			buf[i] = c
		}
	}
	return string(buf)
}

// --- Single byte tests ---

@(test)
test_encode_single_byte_0x00 :: proc(t: ^testing.T) {
	data := [?]u8{0x00}
	expect_bytes_encode_to(t, data[:], "00", "0x00 encodes as itself")
}

@(test)
test_encode_single_byte_0x01 :: proc(t: ^testing.T) {
	data := [?]u8{0x01}
	expect_bytes_encode_to(t, data[:], "01", "0x01 encodes as itself")
}

@(test)
test_encode_single_byte_0x7f :: proc(t: ^testing.T) {
	data := [?]u8{0x7f}
	expect_bytes_encode_to(t, data[:], "7F", "0x7f encodes as itself")
}

// --- Empty string ---

@(test)
test_encode_empty_string :: proc(t: ^testing.T) {
	expect_bytes_encode_to(t, nil, "80", "empty string encodes as 0x80")
}

// --- Short strings ---

@(test)
test_encode_dog :: proc(t: ^testing.T) {
	expect_bytes_encode_to(t, transmute([]u8)string("dog"), "83646F67", "dog encodes correctly")
}

@(test)
test_encode_cat :: proc(t: ^testing.T) {
	expect_bytes_encode_to(t, transmute([]u8)string("cat"), "83636174", "cat encodes correctly")
}

@(test)
test_encode_hello_world :: proc(t: ^testing.T) {
	expect_bytes_encode_to(
		t,
		transmute([]u8)string("hello world"),
		"8B68656C6C6F20776F726C64",
		"hello world encodes correctly",
	)
}

// --- Short string boundary (55 bytes) ---

@(test)
test_encode_55_byte_string :: proc(t: ^testing.T) {
	data: [55]u8
	for i in 0 ..< 55 do data[i] = 'x'
	encoded, err := rlp.encode(rlp.Item(rlp.Bytes(data[:])))
	defer delete(encoded)
	testing.expect(t, err == .None, "55-byte string should encode")
	testing.expect(t, encoded[0] == 0x80 + 55, "55-byte string prefix should be 0xb7")
	testing.expect(t, len(encoded) == 56, "55-byte string should encode to 56 bytes")
}

// --- Long strings (>55 bytes) ---

@(test)
test_encode_56_byte_string :: proc(t: ^testing.T) {
	data: [56]u8
	for i in 0 ..< 56 do data[i] = 'a'
	encoded, err := rlp.encode(rlp.Item(rlp.Bytes(data[:])))
	defer delete(encoded)
	testing.expect(t, err == .None, "56-byte string should encode")
	// 0xb8 = 0xb7 + 1 (one byte for length), then 0x38 = 56
	testing.expect(t, encoded[0] == 0xb8, "56-byte string prefix should be 0xb8")
	testing.expect(t, encoded[1] == 56, "length byte should be 56")
	testing.expect(t, len(encoded) == 58, "56-byte string should encode to 58 bytes")
}

@(test)
test_encode_lorem_ipsum :: proc(t: ^testing.T) {
	lorem := "Lorem ipsum dolor sit amet, consectetur adipisicing elit"
	expect_bytes_encode_to(
		t,
		transmute([]u8)lorem,
		"B8384C6F72656D20697073756D20646F6C6F722073697420616D65742C20636F6E7365637465747572206164697069736963696E6720656C6974",
		"lorem ipsum encodes correctly",
	)
}

// --- Empty list ---

@(test)
test_encode_empty_list :: proc(t: ^testing.T) {
	items: []rlp.Item
	item := rlp.Item(rlp.List(items))
	expect_encodes_to(t, item, "C0", "empty list encodes as 0xc0")
}

// --- Lists ---

@(test)
test_encode_list_cat_dog :: proc(t: ^testing.T) {
	items := [?]rlp.Item{
		rlp.Item(rlp.Bytes(transmute([]u8)string("cat"))),
		rlp.Item(rlp.Bytes(transmute([]u8)string("dog"))),
	}
	item := rlp.Item(rlp.List(items[:]))
	expect_encodes_to(t, item, "C88363617483646F67", "['cat','dog'] encodes correctly")
}

@(test)
test_encode_list_with_empty_string :: proc(t: ^testing.T) {
	items := [?]rlp.Item{
		rlp.Item(rlp.Bytes(nil)),
	}
	item := rlp.Item(rlp.List(items[:]))
	expect_encodes_to(t, item, "C180", "[''] encodes correctly")
}

// --- Nested lists ---

@(test)
test_encode_nested_empty_list :: proc(t: ^testing.T) {
	// [[]]
	inner: []rlp.Item
	inner_list := [?]rlp.Item{rlp.Item(rlp.List(inner))}
	item := rlp.Item(rlp.List(inner_list[:]))
	expect_encodes_to(t, item, "C1C0", "[[]] encodes correctly")
}

@(test)
test_encode_set_theory_3 :: proc(t: ^testing.T) {
	// [ [], [[]], [ [], [[]] ] ]
	empty: []rlp.Item

	inner1 := [?]rlp.Item{rlp.Item(rlp.List(empty))}
	inner2_sub := [?]rlp.Item{rlp.Item(rlp.List(empty)), rlp.Item(rlp.List(inner1[:]))}
	items := [?]rlp.Item{
		rlp.Item(rlp.List(empty)),
		rlp.Item(rlp.List(inner1[:])),
		rlp.Item(rlp.List(inner2_sub[:])),
	}
	item := rlp.Item(rlp.List(items[:]))
	expect_encodes_to(t, item, "C7C0C1C0C3C0C1C0", "set theory 3 encodes correctly")
}

// --- Integer encoding ---

@(test)
test_encode_uint_0 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(0)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(0) should succeed")
	testing.expect(t, len(encoded) == 1 && encoded[0] == 0x80, "0 encodes as empty string (0x80)")
}

@(test)
test_encode_uint_1 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(1)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(1) should succeed")
	testing.expect(t, len(encoded) == 1 && encoded[0] == 0x01, "1 encodes as 0x01")
}

@(test)
test_encode_uint_127 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(127)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(127) should succeed")
	testing.expect(t, len(encoded) == 1 && encoded[0] == 0x7f, "127 encodes as 0x7f")
}

@(test)
test_encode_uint_128 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(128)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(128) should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "8180")
}

@(test)
test_encode_uint_256 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(256)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(256) should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "820100")
}

@(test)
test_encode_uint_1024 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(1024)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(1024) should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "820400")
}

@(test)
test_encode_uint_65535 :: proc(t: ^testing.T) {
	encoded, err := rlp.encode_uint(65535)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode_uint(65535) should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "82FFFF")
}
