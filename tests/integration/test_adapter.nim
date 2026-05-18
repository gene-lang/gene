import unittest
import strutils
import gene/types except Exception
import gene/compiler
import gene/vm
from gene/parser import read

import ../helpers

proc manual_cu(instructions: seq[Instruction]): CompilationUnit =
  let cu = compile(@[read("nil")])
  cu.instructions = instructions
  cu.instruction_traces = newSeq[SourceTrace](instructions.len)
  cu

proc new_manual_vm(cu: CompilationUnit): ptr VirtualMachine =
  let vm = new_vm_ptr()
  vm.frame = new_frame()
  vm.frame.stack_index = 0
  vm.frame.scope = new_scope(new_scope_tracker())
  vm.frame.ns = App.app.gene_ns.ref.ns
  vm.cu = cu
  vm.pc = 0
  vm

proc wrap_interface(gene_interface: GeneInterface): Value =
  let r = new_ref(VkInterface)
  r.gene_interface = gene_interface
  r.to_ref_value()

suite "adapter runtime":
  test_vm """
    (do
      (interface B (method b []))
      (interface A (method a []))
      (class C
        (ctor [] nil)
        (method a [] "A")
        (method b [] "B")
      )
      (implement A for C)
      (implement B for C)
      ((B (A (new C))) .b)
    )
  """, "B"

  test_vm """
    (do
      (interface Ageable
        (method age [] -> Int)
      )
      (implement Ageable for Int
        (field stored_birth_year Int)
        (ctor [birth_year]
          (/stored_birth_year = birth_year)
        )
        (method age []
          (/_wrapped - /stored_birth_year)
        )
      )
      ((Ageable 2026 1990) .age)
    )
  """, 36

  test_vm """
    (do
      (interface Sized (method length []))
      (implement Sized for String)
      ((Sized "abc") .length)
    )
  """, 3

  test_vm """
    (do
      (interface SizedForFalse (method length []))
      (class UnsizedForSatisfies (ctor [] nil))
      (satisfies? (new UnsizedForSatisfies) SizedForFalse)
    )
  """, FALSE

  test_vm """
    (do
      (interface SizedForSatisfies (method length []))
      (implement SizedForSatisfies for String)
      (satisfies? "abc" SizedForSatisfies)
    )
  """, TRUE

  test_vm """
    (do
      (interface Readable (method read []))
      (interface Writable (method write [value]))
      (class Buffer implements [Readable Writable]
        (ctor [] nil)
        (method read [] "r")
        (method write [value] value))
      (var b (new Buffer))
      (if (satisfies? b Readable)
        (if (satisfies? b Writable)
          (((Readable b) .read) ++ ((Writable b) .write "w"))
        else
          "bad")
      else
        "bad")
    )
  """, "rw"

  test_vm """
    (do
      (interface NamedDefault
        (field name String)
        (method display [] -> String
          /name))
      (class Person implements NamedDefault
        (field name String)
        (ctor [name]
          (/name = name)))
      ((NamedDefault (new Person "Ada")) .display)
    )
  """, "Ada"

  test_vm """
    (do
      (interface ExternalNamedDefault
        (field name String)
        (method display [] -> String
          /name))
      (class NamedSource
        (field name String)
        (ctor [name]
          (/name = name)))
      (implement ExternalNamedDefault for NamedSource)
      ((ExternalNamedDefault (new NamedSource "Ada")) .display)
    )
  """, "Ada"

  test_vm """
    (do
      (interface ParentReadable (method read []))
      (interface ParentWritable (method write [value]))
      (interface ParentReadWrite extends [ParentReadable ParentWritable])
      (class ParentBuffer implements ParentReadWrite
        (ctor [] nil)
        (method read [] "r")
        (method write [value] value))
      (var b (new ParentBuffer))
      (if (satisfies? b ParentReadable)
        (((ParentReadable b) .read) ++ ((ParentWritable b) .write "w"))
      else
        "bad")
    )
  """, "rw"

  test_vm_error """
    (do
      (interface DefaultA
        (method label [] "a"))
      (interface DefaultB
        (method label [] "b"))
      (interface DefaultConflict extends [DefaultA DefaultB])
    )
  """

  test_vm """
    (do
      (interface OverrideDefaultA
        (method label [] "a"))
      (interface OverrideDefaultB
        (method label [] "b"))
      (interface OverrideDefaultC extends [OverrideDefaultA OverrideDefaultB]
        (method label [] "c"))
      (class OverrideDefaultClass implements OverrideDefaultC
        (ctor [] nil))
      ((OverrideDefaultC (new OverrideDefaultClass)) .label)
    )
  """, "c"

  test_vm_error """
    (do
      (interface ClassDefaultA
        (method label [] "a"))
      (interface ClassDefaultB
        (method label [] "b"))
      (class DefaultConflictClass implements [ClassDefaultA ClassDefaultB]
        (ctor [] nil))
    )
  """

  test_vm """
    (do
      (interface ClassOverrideDefaultA
        (method label [] "a"))
      (interface ClassOverrideDefaultB
        (method label [] "b"))
      (class ClassOverrideDefault implements [ClassOverrideDefaultA ClassOverrideDefaultB]
        (ctor [] nil)
        (method label [] "c"))
      ((ClassOverrideDefaultA (new ClassOverrideDefault)) .label)
    )
  """, "c"

  test_vm """
    (do
      (interface Sum3 (method sum3 [a b c]))
      (class C
        (ctor [] nil)
        (method sum3 [a b c] ((a + b) + c))
      )
      (implement Sum3 for C)
      ((Sum3 (new C)) .sum3 1 2 3)
    )
  """, 6

  test_vm_error """
    (do
      (interface Sum3 (method sum3 [a b c]))
      (class ShortSum
        (ctor [] nil)
        (method sum3 [a b] (a + b)))
      (implement Sum3 for ShortSum)
    )
  """

  test_vm """
    (do
      (interface Sum3 (method sum3 [a b c]))
      (class C
        (ctor [] nil)
        (method sum3 [a b c] ((a + b) + c))
      )
      (implement Sum3 for C)
      (var method_name "sum3")
      ((Sum3 (new C)) . method_name 1 2 3)
    )
  """, 6

  test_vm """
    (do
      (interface Readable (method read []))
      (class C
        (ctor [] (/x = 1))
      )
      (implement Readable for C
        (method read [] /_wrapped/x)
      )
      (var r (Readable (new C)))
      (var m r/read)
      (m)
    )
  """, 1

  test_vm_error """
    (do
      (interface Readable (method read []))
      (class MissingReadable
        (ctor [] nil))
      (implement Readable for MissingReadable)
    )
  """

  test_vm """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name ^from label))
      (var source (new Source "Ada"))
      (var named (Named source))
      (named/name = "Grace")
      [named/name source/label]
    )
  """, @["Grace", "Grace"]

  test_vm_error """
    (do
      (interface NamedString (field name String))
      (class WrongNamed
        (field name Int)
        (ctor []
          (/name = 1)))
      (implement NamedString for WrongNamed)
    )
  """

  test_vm """
    (do
      (interface Labeled (field display String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Labeled for Source
        (field display
          (get [] /_wrapped/label)
          (set [v] (/_wrapped/label = v))))
      (var source (new Source "Ada"))
      (var labeled (Labeled source))
      (labeled/display = "Grace")
      [labeled/display source/label]
    )
  """, @["Grace", "Grace"]

  test_vm """
    (do
      (interface Ageable
        (field birth_year Int ^readonly true)
        (method age []))
      (implement Ageable for Int
        (field stored_birth_year Int)
        (ctor [birth_year]
          (/stored_birth_year = birth_year))
        (field birth_year
          (get [] /stored_birth_year))
        (method age []
          (/_wrapped - /stored_birth_year)))
      (var ageable (Ageable 2026 1990))
      [ageable/birth_year (ageable .age)]
    )
  """, @[1990, 36]

  test_vm_error """
    (do
      (interface Ageable
        (method age []))
      (implement Ageable for Int
        (field stored_birth_year Int)
        (ctor [birth_year]
          (/stored_birth_year = birth_year))
        (method age []
          (/_wrapped - /stored_birth_year)))
      (var ageable (Ageable 2026 1990))
      ageable/stored_birth_year
    )
  """

  test_vm_error """
    (do
      (interface IdView (field id Int ^readonly true))
      (class Source
        (ctor []
          (/raw_id = 1)))
      (implement IdView for Source
        (field id ^from raw_id))
      (var view (IdView (new Source)))
      (view/id = 2)
    )
  """

  test_vm_error """
    (do
      (interface Labeled (field display String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Labeled for Source
        (field display
          (get [] /_wrapped/label)))
      (var labeled (Labeled (new Source "Ada")))
      (labeled/display = "Grace")
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field display_name ^from label))
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name ^from label)
        (field name ^from label))
    )
  """

  test_vm_error """
    (do
      (interface Ageable (field birth_year Int))
      (implement Ageable for Int
        (field birth_year Int))
    )
  """

  test_vm_error """
    (do
      (interface Ageable)
      (implement Ageable for Int
        (field stored_birth_year Int)
        (field stored_birth_year Int))
    )
  """

  test_vm_error """
    (do
      (interface Ageable)
      (implement Ageable for Int
        (ctor [birth_year]
          (/stored_birth_year = birth_year)))
      (Ageable 2026 1990)
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name
          (set [v] (/_wrapped/label = v))))
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name
          (get [x] /_wrapped/label)))
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name
          (fetch [] /_wrapped/label)))
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [label]
          (/label = label)))
      (implement Named for Source
        (field name ^from label
          (get [] /_wrapped/label)))
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (class Source
        (ctor [] nil))
      (implement Named for Source)
      (var named (Named (new Source)))
      named/name
    )
  """

  test_vm_error """
    (do
      (interface Named (field name String))
      (implement Named for Int
        (field name ^from label))
      (var named (Named 1))
      (named/name = "Grace")
    )
  """

  test_vm """
    (do
      (interface Marker)
      ((Marker .class) .name)
    )
  """, "Interface"

  test_vm """
    (do
      (interface Sized (method length []))
      (implement Sized for String)
      (((Sized "abc") .class) .name)
    )
  """, "Adapter"

  test_vm_error """
    (do
      (interface View)
      (class C (ctor [] nil))
      (implement View for C)
      (var v (View (new C)))
      (v/secret = 1)
    )
  """

  test "IkAdapter remains executable for legacy GIR":
    init_all()

    let gene_interface = new_interface("LegacySized", "tests/adapter")
    gene_interface.add_method("length")
    let interface_val = wrap_interface(gene_interface)

    let impl = new_implementation(gene_interface, App.app.string_class.ref.class)
    App.app.string_class.ref.class.register_implementation(gene_interface, impl)

    let cu = manual_cu(@[
      Instruction(kind: IkStart),
      Instruction(kind: IkPushValue, arg0: interface_val),
      Instruction(kind: IkPushValue, arg0: "abc".to_value()),
      Instruction(kind: IkAdapter),
      Instruction(kind: IkEnd),
    ])
    let vm = new_manual_vm(cu)
    let result = vm.exec()
    free_vm_ptr(vm)

    check result.kind == VkAdapter
    check result.ref.adapter.gene_interface == gene_interface
    check result.ref.adapter.inner == "abc".to_value()

  test "IkUnifiedCallDynamic supports interface targets":
    init_all()

    let gene_interface = new_interface("DynamicSized", "tests/adapter")
    gene_interface.add_method("length")
    let interface_val = wrap_interface(gene_interface)

    let impl = new_implementation(gene_interface, App.app.string_class.ref.class)
    App.app.string_class.ref.class.register_implementation(gene_interface, impl)

    let cu = manual_cu(@[
      Instruction(kind: IkStart),
      Instruction(kind: IkPushValue, arg0: interface_val),
      Instruction(kind: IkCallArgsStart),
      Instruction(kind: IkPushValue, arg0: "abc".to_value()),
      Instruction(kind: IkUnifiedCallDynamic),
      Instruction(kind: IkEnd),
    ])
    let vm = new_manual_vm(cu)
    let result = vm.exec()
    free_vm_ptr(vm)

    check result.kind == VkAdapter
    check result.ref.adapter.gene_interface == gene_interface
    check result.ref.adapter.inner == "abc".to_value()

  test "Computed adapter props reject writes instead of shadowing":
    init_all()

    let gene_interface = new_interface("ClockView", "tests/adapter")
    gene_interface.add_prop("now")

    let impl = new_implementation(gene_interface, App.app.int_class.ref.class)
    impl.map_prop_computed("now", NIL)

    let adapter = new_adapter(gene_interface, 1.to_value(), impl)
    let r = new_ref(VkAdapter)
    r.adapter = adapter
    let adapter_val = r.to_ref_value()
    let binding_name = "__adapter_clock_view__"

    App.app.gene_ns.ns[binding_name.to_key()] = adapter_val
    App.app.global_ns.ns[binding_name.to_key()] = adapter_val

    try:
      discard VM.exec("(" & binding_name & "/now = 5)", "test_code")
      fail()
    except CatchableError as ex:
      check ex.msg.contains("Computed property")
