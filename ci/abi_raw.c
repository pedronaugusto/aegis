/* Independent C translation unit: scalar arguments, returns and record fields.
 * The promised ABI excludes 128-bit integers. No headers/libc are required. */
#define RAW(NAME, TYPE) \
    struct raw_record_##NAME { unsigned char before; TYPE value; TYPE after; }; \
    TYPE raw_exchange_##NAME(TYPE value, TYPE salt) { return value ^ salt; } \
    TYPE raw_field_##NAME(const struct raw_record_##NAME *record) { \
        return record->value ^ record->after ^ (TYPE)(record->before & 0x7f); \
    }
RAW(u8, __UINT8_TYPE__)
RAW(i8, __INT8_TYPE__)
RAW(u16, __UINT16_TYPE__)
RAW(i16, __INT16_TYPE__)
RAW(u32, __UINT32_TYPE__)
RAW(i32, __INT32_TYPE__)
RAW(u64, __UINT64_TYPE__)
RAW(i64, __INT64_TYPE__)
RAW(usize, __UINTPTR_TYPE__)
RAW(isize, __INTPTR_TYPE__)
