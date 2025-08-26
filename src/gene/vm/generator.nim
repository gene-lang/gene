import ../types
import strformat

# Initialize generator support
proc init_generator*() =
  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return
    
    let generator_class = new_class("Generator")
    
    # Add next method - for now just returns VOID
    proc generator_next(self: VirtualMachine, args: Value): Value =
      # Get next value from generator
      if args.kind != VkGene:
        raise new_exception(types.Exception, fmt"Generator.next expects Gene args, got {args.kind}")
      if args.gene.children.len < 1:
        raise new_exception(types.Exception, "Generator.next requires a generator")
      
      let gen_arg = args.gene.children[0]
      if gen_arg.kind != VkGenerator:
        raise new_exception(types.Exception, "next can only be called on a Generator")
      
      # Cast the generator pointer to GeneratorObj
      let gen = cast[ptr GeneratorObj](gen_arg.ref.generator)
      
      # Check if generator is nil
      if gen == nil:
        return NOT_FOUND
      
      # If we have a peeked value, return it and clear the peek
      if gen != nil and gen.has_peeked:
        gen.has_peeked = false
        let val = gen.peeked_value
        gen.peeked_value = NIL
        return val
      
      # Otherwise, get the next value normally
      # For now, always return NOT_FOUND until full implementation
      if gen.done:
        return NOT_FOUND
      else:
        # TODO: Actually execute generator until next yield
        return NOT_FOUND

    proc generator_has_next(self: VirtualMachine, args: Value): Value =
      # Check if generator has a next value without consuming it
      if args.kind != VkGene:
        raise new_exception(types.Exception, fmt"Generator.has_next expects Gene args, got {args.kind}")
      if args.gene.children.len < 1:
        raise new_exception(types.Exception, "Generator.has_next requires a generator")
      
      let gen_arg = args.gene.children[0]
      if gen_arg.kind != VkGenerator:
        raise new_exception(types.Exception, "has_next can only be called on a Generator")
      
      # Cast the generator pointer to GeneratorObj
      let gen = cast[ptr GeneratorObj](gen_arg.ref.generator)
      
      # Check if generator is nil
      if gen == nil:
        return FALSE
      
      # If we already have a peeked value, return true
      if gen.has_peeked:
        return TRUE
      
      # If generator is done, return false
      if gen.done:
        return FALSE
      
      # Otherwise, try to get the next value without consuming it
      # For now, since we always return NOT_FOUND, peek that
      let next_val = NOT_FOUND  # TODO: Actually execute generator to get next value
      
      # Store the peeked value
      if next_val == NOT_FOUND:
        gen.done = true
        return FALSE
      else:
        gen.has_peeked = true
        gen.peeked_value = next_val
        return TRUE

    # Add methods to generator class
    generator_class.def_native_method("next", generator_next)
    generator_class.def_native_method("has_next", generator_has_next)
    
    # Store in Application
    let generator_class_ref = new_ref(VkClass)
    generator_class_ref.class = generator_class
    App.app.generator_class = generator_class_ref.to_ref_value()
    
    # Add to gene namespace if it exists
    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Generator".to_key()] = App.app.generator_class

# Call init_generator to register the callback
init_generator()