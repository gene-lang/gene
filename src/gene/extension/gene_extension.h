/**
 * Gene VM C Extension API
 * 
 * This header provides the C interface for creating Gene VM extensions.
 * Extensions must export two functions:
 *   - void set_globals(VirtualMachine* vm)
 *   - Namespace* init(VirtualMachine* vm)
 */

#ifndef GENE_EXTENSION_H
#define GENE_EXTENSION_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========== Opaque Types ========== */

/**
 * VirtualMachine - The Gene VM instance
 * Opaque pointer - internal structure not exposed to extensions
 */
typedef struct VirtualMachine VirtualMachine;

/**
 * Namespace - A Gene namespace (collection of key-value pairs)
 * Opaque pointer - use gene_namespace_* functions to manipulate
 */
typedef struct Namespace Namespace;

/* ========== Value Type ========== */

/**
 * Value - A Gene value (NaN-boxed 64-bit value)
 * Can represent integers, floats, strings, objects, etc.
 * Use gene_to_* and gene_from_* functions to convert
 */
typedef uint64_t Value;

/**
 * Key - A symbol key for namespace lookups
 * Opaque 64-bit value - use gene_to_key() to create
 */
typedef uint64_t Key;

/* ========== Function Types ========== */

/**
 * NativeFn - Function pointer type for native functions
 * 
 * @param vm - The VM instance
 * @param args - Array of argument values
 * @param arg_count - Number of arguments
 * @param has_keyword_args - Whether keyword arguments are present
 * @return Value - The return value
 */
typedef Value (*NativeFn)(VirtualMachine* vm, Value* args, 
                          int arg_count, bool has_keyword_args);

/**
 * SetGlobalsFn - Function type for set_globals export
 * Called by VM to pass VM pointer to extension
 */
typedef void (*SetGlobalsFn)(VirtualMachine* vm);

/**
 * InitFn - Function type for init export
 * Called by VM to initialize extension and get its namespace
 */
typedef Namespace* (*InitFn)(VirtualMachine* vm);

/* ========== Value Conversion Functions ========== */

/**
 * Convert C int64 to Gene Value
 */
extern Value gene_to_value_int(int64_t i);

/**
 * Convert C double to Gene Value
 */
extern Value gene_to_value_float(double f);

/**
 * Convert C string to Gene Value
 * Note: String is copied, caller retains ownership of input
 */
extern Value gene_to_value_string(const char* s);

/**
 * Convert C bool to Gene Value
 */
extern Value gene_to_value_bool(bool b);

/**
 * Get NIL value
 */
extern Value gene_nil(void);

/**
 * Convert Gene Value to C int64
 * Returns 0 if value is not an integer
 */
extern int64_t gene_to_int(Value v);

/**
 * Convert Gene Value to C double
 * Returns 0.0 if value is not a number
 */
extern double gene_to_float(Value v);

/**
 * Convert Gene Value to C string
 * Returns NULL if value is not a string
 * Note: Returned pointer is owned by Gene VM, do not free
 */
extern const char* gene_to_string(Value v);

/**
 * Convert Gene Value to C bool
 * Returns false for NIL and false, true for everything else
 */
extern bool gene_to_bool(Value v);

/**
 * Check if value is NIL
 */
extern bool gene_is_nil(Value v);

/* ========== Namespace Functions ========== */

/**
 * Create a new namespace with given name
 */
extern Namespace* gene_new_namespace(const char* name);

/**
 * Set a value in a namespace
 * 
 * @param ns - The namespace
 * @param key - The key (symbol name as string)
 * @param value - The value to set
 */
extern void gene_namespace_set(Namespace* ns, const char* key, Value value);

/**
 * Get a value from a namespace
 * Returns NIL if key not found
 */
extern Value gene_namespace_get(Namespace* ns, const char* key);

/* ========== Function Wrapping ========== */

/**
 * Wrap a C function pointer as a Gene Value
 * The returned Value can be stored in a namespace
 */
extern Value gene_wrap_native_fn(NativeFn fn);

/* ========== Argument Helpers ========== */

/**
 * Get positional argument at index
 * Handles keyword arguments correctly
 * Returns NIL if index out of bounds
 */
extern Value gene_get_arg(Value* args, int arg_count, bool has_keyword_args, int index);

/* ========== Error Handling ========== */

/**
 * Raise an exception with given message
 * Does not return
 */
extern void gene_raise_error(const char* message);

#ifdef __cplusplus
}
#endif

#endif /* GENE_EXTENSION_H */

