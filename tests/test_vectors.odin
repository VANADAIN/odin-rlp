package rlp_tests

import "core:testing"
import "core:encoding/hex"
import "core:math/big"
import rlp "../rlp"

// Ethereum RLP test vectors.
// Sources: Ethereum wiki, Yellow Paper Appendix B.

// Full encode-decode roundtrip vectors
RLP_Vector :: struct {
	description: string,
	expected_hex: string,
}

@(test)
test_vector_single_bytes :: proc(t: ^testing.T) {
	// All single bytes 0x00-0x7f encode as themselves
	for b in u8(0x00) ..= u8(0x7f) {
		data := [1]u8{b}
		encoded, err := rlp.encode(rlp.Item(rlp.Bytes(data[:])))
		defer delete(encoded)

		testing.expect(t, err == .None, "single byte encode should succeed")
		testing.expect(t, len(encoded) == 1, "single byte should encode to 1 byte")
		testing.expect(t, encoded[0] == b, "single byte should encode as itself")
	}
}

@(test)
test_vector_single_byte_0x80 :: proc(t: ^testing.T) {
	// 0x80 is NOT a single byte (>= 0x80), so it gets short string encoding
	data := [1]u8{0x80}
	encoded, err := rlp.encode(rlp.Item(rlp.Bytes(data[:])))
	defer delete(encoded)

	testing.expect(t, err == .None, "0x80 encode should succeed")
	testing.expect(t, len(encoded) == 2, "0x80 should encode to 2 bytes")
	testing.expect(t, encoded[0] == 0x81, "prefix should be 0x81")
	testing.expect(t, encoded[1] == 0x80, "data should be 0x80")
}

@(test)
test_vector_encode_address :: proc(t: ^testing.T) {
	// Ethereum zero address (20 bytes of 0x00)
	addr: [20]u8
	encoded, err := rlp.encode_address(addr)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode address should succeed")
	// 20 bytes -> short string: 0x80 + 20 = 0x94 prefix
	testing.expect(t, encoded[0] == 0x94, "address prefix should be 0x94")
	testing.expect(t, len(encoded) == 21, "address should encode to 21 bytes")
}

@(test)
test_vector_encode_big_int :: proc(t: ^testing.T) {
	val: big.Int
	defer big.destroy(&val)
	big.set(&val, 1024)

	encoded, err := rlp.encode_big_int(&val)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode big int should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "820400")
}

@(test)
test_vector_encode_big_int_zero :: proc(t: ^testing.T) {
	val: big.Int
	defer big.destroy(&val)
	big.set(&val, 0)

	encoded, err := rlp.encode_big_int(&val)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode big int 0 should succeed")
	testing.expect(t, len(encoded) == 1 && encoded[0] == 0x80, "big int 0 should encode as 0x80")
}

@(test)
test_vector_encode_big_int_large :: proc(t: ^testing.T) {
	// 0xFFFFFFFF = 4294967295
	val: big.Int
	defer big.destroy(&val)
	big.atoi(&val, "FFFFFFFF", 16)

	encoded, err := rlp.encode_big_int(&val)
	defer delete(encoded)
	testing.expect(t, err == .None, "encode big int should succeed")

	got_hex_b := hex.encode(encoded)
	defer delete(got_hex_b)
	upper := to_upper(string(got_hex_b))
	defer delete(upper)
	testing.expect_value(t, upper, "84FFFFFFFF")
}

// Comprehensive encode -> decode roundtrip for all types
@(test)
test_roundtrip_all_uint_sizes :: proc(t: ^testing.T) {
	values := [?]u64{0, 1, 127, 128, 255, 256, 1024, 65535, 0xFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF_FFFF}
	for val in values {
		encoded, err := rlp.encode_uint(val)
		testing.expect(t, err == .None, "encode_uint should succeed")

		decoded, derr := rlp.decode(encoded)
		testing.expect(t, derr == .None, "decode should succeed")

		// Verify we can read back the value
		bytes, is_bytes := decoded.(rlp.Bytes)
		testing.expect(t, is_bytes, "decoded should be bytes")

		if is_bytes {
			// Convert decoded bytes back to u64
			result: u64
			for b in bytes {
				result = result << 8 | u64(b)
			}
			testing.expect(t, result == val, "roundtrip value should match")
		}

		delete(encoded)
		rlp.item_destroy(&decoded)
	}
}

@(test)
test_roundtrip_various_string_lengths :: proc(t: ^testing.T) {
	// Test boundary lengths: 0, 1, 54, 55, 56, 100, 255, 256
	for slen in ([?]int{0, 1, 54, 55, 56, 100, 255, 256}) {
		data := make([]u8, slen)
		defer delete(data)
		for i in 0 ..< slen do data[i] = u8(i % 256)

		// Avoid single-byte rule for len=1 by ensuring byte >= 0x80
		if slen == 1 do data[0] = 0x80

		encoded, err := rlp.encode(rlp.Item(rlp.Bytes(data)))
		testing.expect(t, err == .None, "encode should succeed")

		decoded, derr := rlp.decode(encoded)
		testing.expect(t, derr == .None, "decode should succeed")
		expect_decoded_bytes(t, decoded, data, "roundtrip should preserve data")

		delete(encoded)
		rlp.item_destroy(&decoded)
	}
}

@(test)
test_decode_with_rest :: proc(t: ^testing.T) {
	// Two concatenated RLP items
	enc1, _ := rlp.encode(rlp.Item(rlp.Bytes(transmute([]u8)string("cat"))))
	defer delete(enc1)
	enc2, _ := rlp.encode(rlp.Item(rlp.Bytes(transmute([]u8)string("dog"))))
	defer delete(enc2)

	combined := make([]u8, len(enc1) + len(enc2))
	defer delete(combined)
	copy(combined, enc1)
	copy(combined[len(enc1):], enc2)

	item1, rest, err1 := rlp.decode_with_rest(combined)
	defer rlp.item_destroy(&item1)
	testing.expect(t, err1 == .None, "first decode should succeed")
	expect_decoded_bytes(t, item1, transmute([]u8)string("cat"), "first should be 'cat'")
	testing.expect(t, len(rest) == len(enc2), "rest should have correct length")

	item2, rest2, err2 := rlp.decode_with_rest(rest)
	defer rlp.item_destroy(&item2)
	testing.expect(t, err2 == .None, "second decode should succeed")
	expect_decoded_bytes(t, item2, transmute([]u8)string("dog"), "second should be 'dog'")
	testing.expect(t, len(rest2) == 0, "no remaining bytes")
}
