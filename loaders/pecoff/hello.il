// source: ECMA 335, Partition II, 4.1
.assembly extern mscorlib {} 
.assembly hello {} 
.method static public void main() cil managed 
{ 
  .entrypoint 
  .maxstack 1 
  ldstr "Hello world!" 
  call void [mscorlib]System.Console::WriteLine(class System.String) 
  ret 
}