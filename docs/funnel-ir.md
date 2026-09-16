# Funnel IR Representation

```IrProc {
  name = "return_item",
  params = [ item: Item, reason: Char(3) ],
  requires = [
    CallRule("returnable", [item]),
    NotEq(FieldRef("item", "state"), EnumVal("State", "RETURNED"))
  ],
  body = [
    Assign(FieldRef("item", "state"),  EnumVal("State", "RETURNED")),
    Assign(FieldRef("item", "reason"), ParamRef("reason")),
    EmitEffect(Update("item")),
    EmitEffect(Commit)
  ],
  effects = [
    Update("Item"), Commit
  ]
}
```
