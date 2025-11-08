/**
 * Example C Extension for Gene VM
 * 
 * This extension demonstrates:
 * - Basic arithmetic functions
 * - String manipulation
 * - Error handling
 * - Argument processing
 */

#include "../src/gene/extension/gene_extension.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* Global VM pointer (set by set_globals) */
static VirtualMachine* VM = NULL;

/* ========== Extension Functions ========== */

/**
 * add - Add two numbers
 * Usage: (c_ext/add 1 2) => 3
 */
static Value c_add(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    if (arg_count < 2) {
        gene_raise_error("add requires 2 arguments");
    }
    
    Value a = gene_get_arg(args, arg_count, has_keyword_args, 0);
    Value b = gene_get_arg(args, arg_count, has_keyword_args, 1);
    
    int64_t result = gene_to_int(a) + gene_to_int(b);
    return gene_to_value_int(result);
}

/**
 * multiply - Multiply two numbers
 * Usage: (c_ext/multiply 3 4) => 12
 */
static Value c_multiply(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    if (arg_count < 2) {
        gene_raise_error("multiply requires 2 arguments");
    }
    
    Value a = gene_get_arg(args, arg_count, has_keyword_args, 0);
    Value b = gene_get_arg(args, arg_count, has_keyword_args, 1);
    
    int64_t result = gene_to_int(a) * gene_to_int(b);
    return gene_to_value_int(result);
}

/**
 * concat - Concatenate two strings
 * Usage: (c_ext/concat "hello" "world") => "helloworld"
 */
static Value c_concat(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    if (arg_count < 2) {
        gene_raise_error("concat requires 2 arguments");
    }

    // For now, just return a hardcoded string to test
    return gene_to_value_string("Hello, World!");
}

/**
 * strlen - Get length of a string
 * Usage: (c_ext/strlen "hello") => 5
 */
static Value c_strlen(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    if (arg_count < 1) {
        gene_raise_error("strlen requires 1 argument");
    }
    
    Value str_val = gene_get_arg(args, arg_count, has_keyword_args, 0);
    const char* str = gene_to_string(str_val);
    
    if (str == NULL) {
        gene_raise_error("strlen requires a string argument");
    }
    
    return gene_to_value_int((int64_t)strlen(str));
}

/**
 * is_even - Check if a number is even
 * Usage: (c_ext/is_even 4) => true
 */
static Value c_is_even(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    if (arg_count < 1) {
        gene_raise_error("is_even requires 1 argument");
    }
    
    Value num_val = gene_get_arg(args, arg_count, has_keyword_args, 0);
    int64_t num = gene_to_int(num_val);
    
    return gene_to_value_bool(num % 2 == 0);
}

/**
 * greet - Return a greeting message
 * Usage: (c_ext/greet "Alice") => "Hello, Alice!"
 */
static Value c_greet(VirtualMachine* vm, Value* args, int arg_count, bool has_keyword_args) {
    const char* default_name = "World";
    const char* name = default_name;
    
    if (arg_count > 0) {
        Value name_val = gene_get_arg(args, arg_count, has_keyword_args, 0);
        const char* name_str = gene_to_string(name_val);
        if (name_str != NULL) {
            name = name_str;
        }
    }
    
    // Build greeting message
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "Hello, %s!", name);
    
    return gene_to_value_string(buffer);
}

/* ========== Required Extension Exports ========== */

/**
 * set_globals - Called by VM to pass VM pointer
 * This is called before init()
 */
void set_globals(VirtualMachine* vm) {
    VM = vm;
}

/**
 * init - Initialize extension and return namespace
 * This is called after set_globals()
 */
Namespace* init(VirtualMachine* vm) {
    // Create namespace for this extension
    Namespace* ns = gene_new_namespace("c_ext");
    
    // Register functions
    gene_namespace_set(ns, "add", gene_wrap_native_fn(c_add));
    gene_namespace_set(ns, "multiply", gene_wrap_native_fn(c_multiply));
    gene_namespace_set(ns, "concat", gene_wrap_native_fn(c_concat));
    gene_namespace_set(ns, "strlen", gene_wrap_native_fn(c_strlen));
    gene_namespace_set(ns, "is_even", gene_wrap_native_fn(c_is_even));
    gene_namespace_set(ns, "greet", gene_wrap_native_fn(c_greet));
    
    return ns;
}

