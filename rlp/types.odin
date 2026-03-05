package rlp

// Recursive Length Prefix (RLP) encoding types.
// Reference: https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/

// An RLP item is either a byte string or a list of RLP items.
Item :: union {
	Bytes,
	List,
}

Bytes :: distinct []u8
List :: distinct []Item

Error :: enum {
	None,
	Buffer_Too_Small,
	Invalid_Input,
	Unexpected_End,
	Non_Canonical,
	Alloc_Failed,
}

// Destroy an item and all nested items, freeing allocated memory.
item_destroy :: proc(item: ^Item, allocator := context.allocator) {
	switch v in item {
	case Bytes:
		delete(v, allocator)
	case List:
		for &child in v {
			item_destroy(&child, allocator)
		}
		delete(v, allocator)
	}
	item^ = nil
}
