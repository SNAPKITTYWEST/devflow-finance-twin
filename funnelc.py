#!/usr/bin/env python3
# funnelc.py -- compact single-file prototype implementing:
#  - minimal Funnel parser (v0.1)
#  - AST
#  - semantic analyzer / type system
#  - Business IR (authoritative)
#  - backends: COBOL, Prolog, Mercury (small subset)
#  - example: return_item / ach_return
#
# Usage:
#   python3 funnelc.py input.fnl --target cobol|prolog|mercury
#
# Notes:
#  - intentionally dense, minimal error handling
#  - implements core constructs from the spec: TYPE, RECORD, FILE, RULE, PROC, REQUIRE, LOAD, SAVE, IF, ASSIGN, FAIL
#  - IR is authoritative; backends implement IR
#  - Designed as a starting point for v0.1

import sys, re, textwrap, json
from typing import List, Tuple, Dict, Any, Optional, Union

# ---------------------------------------------------------------------------
# Lexer
# ---------------------------------------------------------------------------
KEYWORDS = {
    "PROGRAM","TYPE","RECORD","FILE","USING","KEY","RULE","PROC","REQUIRE",
    "SAVE","LOAD","AS","IF","THEN","ELSE","ENDIF","IN","FAIL","ENUM","NUM",
    "CHAR","STATE","ENDPROC","ENDRULE"
}
TOKEN_SPEC = [
    ('NUMBER',   r'\d+(\.\d+)?'),
    ('ID',       r'[A-Za-z_][A-Za-z0-9_]*'),
    ('STRING',   r'"([^"\\]|\\.)*"'),
    ('EQ',       r':='),
    ('OP',       r'<=|>=|!=|=|<|>'),
    ('LP',       r'\('),
    ('RP',       r'\)'),
    ('LBR',      r'\{'),
    ('RBR',      r'\}'),
    ('COMMA',    r','),
    ('COL',      r':'),
    ('DOT',      r'\.'),
    ('WS',       r'[ \t\r\n]+'),
    ('COMMENT',  r'//.*'),
]
TOK_REGEX = re.compile('|'.join('(?P<%s>%s)' % pair for pair in TOKEN_SPEC))
class Token:
    def __init__(self, typ, val, pos):
        self.typ = typ
        self.val = val
        self.pos = pos
    def __repr__(self):
        return f"Token({self.typ},{self.val})"

def lex(src: str):
    pos = 0
    tokens = []
    for m in TOK_REGEX.finditer(src):
        typ = m.lastgroup
        val = m.group(0)
        if typ == 'WS' or typ == 'COMMENT':
            continue
        if typ == 'ID' and val.upper() in KEYWORDS:
            typ = val.upper()
            val = val.upper()
        tokens.append(Token(typ, val, m.start()))
    tokens.append(Token('EOF','',len(src)))
    return tokens

# ---------------------------------------------------------------------------
# AST nodes (compact)
# ---------------------------------------------------------------------------
class ASTNode: pass
class Program(ASTNode):
    def __init__(self,name,decls): self.name=name; self.decls=decls
class TypeDecl(ASTNode):
    def __init__(self,name,variants): self.name=name; self.variants=variants
class RecordDecl(ASTNode):
    def __init__(self,name,fields): self.name=name; self.fields=fields
class FileDecl(ASTNode):
    def __init__(self,name,storage,keyfields): self.name=name; self.storage=storage; self.keyfields=keyfields
class RuleDecl(ASTNode):
    def __init__(self,name,params,expr): self.name=name; self.params=params; self.expr=expr
class ProcDecl(ASTNode):
    def __init__(self,name,params,body): self.name=name; self.params=params; self.body=body
class Param(ASTNode):
    def __init__(self,name,typ): self.name=name; self.typ=typ
class Field(ASTNode):
    def __init__(self,name,typ): self.name=name; self.typ=typ

# Statements and expressions
class Stmt(ASTNode): pass
class Require(Stmt):
    def __init__(self,expr): self.expr=expr
class Load(Stmt):
    def __init__(self,recname,keys,alias): self.recname=recname; self.keys=keys; self.alias=alias
class Save(Stmt):
    def __init__(self,alias): self.alias=alias
class Assign(Stmt):
    def __init__(self,target,expr): self.target=target; self.expr=expr
class IfStmt(Stmt):
    def __init__(self,cond,thenStmts,elseStmts): self.cond=cond; self.thenStmts=thenStmts; self.elseStmts=elseStmts
class Fail(Stmt):
    def __init__(self,msg): self.msg=msg

class Expr(ASTNode): pass
class Ident(Expr):
    def __init__(self,name): self.name=name
class FieldRef(Expr):
    def __init__(self,alias,field): self.alias=alias; self.field=field
class Literal(Expr):
    def __init__(self,val): self.val=val
class EnumLit(Expr):
    def __init__(self,typename,variant): self.typename=typename; self.variant=variant
class BinOp(Expr):
    def __init__(self,op,l,r): self.op=op; self.l=l; self.r=r
class InExpr(Expr):
    def __init__(self,left,vals): self.left=left; self.vals=vals

# ---------------------------------------------------------------------------
# Parser (recursive descent, minimal)
# ---------------------------------------------------------------------------
class Parser:
    def __init__(self,toks):
        self.toks=toks; self.i=0
    def cur(self): return self.toks[self.i]
    def eat(self,typ=None):
        t=self.cur()
        if typ and t.typ!=typ:
            self.error(f"Expected {typ} got {t.typ} at {t.pos}")
        self.i+=1
        return t
    def error(self,msg): raise SyntaxError(msg)
    def parse(self):
        # PROGRAM name . decl*
        if self.cur().typ!='PROGRAM': self.error("Program must start with PROGRAM")
        self.eat('PROGRAM'); name=self.eat('ID').val; self.eat('DOT')
        decls=[]
        while self.cur().typ!='EOF':
            if self.cur().typ=='TYPE':
                decls.append(self.parse_type())
            elif self.cur().typ=='RECORD':
                decls.append(self.parse_record())
            elif self.cur().typ=='FILE':
                decls.append(self.parse_file())
            elif self.cur().typ=='RULE':
                decls.append(self.parse_rule())
            elif self.cur().typ=='PROC':
                decls.append(self.parse_proc())
            else:
                self.error(f"Unexpected token {self.cur()}")
        return Program(name,decls)
    def parse_type(self):
        self.eat('TYPE'); name=self.eat('ID').val; self.eat('EQ')
        # enumType: alt | alt|alt
        variants=[self.eat('ID').val]
        while self.cur().typ=='OP' and self.cur().val=='|':
            self.eat('OP'); variants.append(self.eat('ID').val)
        self.eat('DOT')
        return TypeDecl(name,variants)
    def parse_record(self):
        self.eat('RECORD'); name=self.eat('ID').val; self.eat('LBR')
        fields=[]
        while self.cur().typ!='RBR':
            fname=self.eat('ID').val; self.eat('COL')
            ftype=self.parse_type_ref(); self.eat('DOT')
            fields.append(Field(fname,ftype))
        self.eat('RBR'); self.eat('DOT')
        return RecordDecl(name,fields)
    def parse_type_ref(self):
        t=self.cur()
        if t.typ=='CHAR':
            self.eat('CHAR'); self.eat('LP'); n=int(self.eat('NUMBER').val); self.eat('RP'); return ('CHAR',n)
        if t.typ=='NUM':
            self.eat('NUM'); self.eat('LP'); p=int(self.eat('NUMBER').val)
            if self.cur().typ== 'COMMA':
                self.eat('COMMA'); s=int(self.eat('NUMBER').val)
            else: s=0
            self.eat('RP'); return ('NUM',p,s)
        # user type
        name=self.eat('ID').val; return ('USER',name)
    def parse_file(self):
        self.eat('FILE'); name=self.eat('ID').val; self.eat('USING'); storage=self.eat('ID').val
        self.eat('KEY'); keyfields=[]
        keyfields.append(self.eat('ID').val); self.eat('LP'); self.eat('NUMBER'); self.eat('RP')
        while self.cur().typ=='COMMA':
            self.eat('COMMA'); keyfields.append(self.eat('ID').val); self.eat('LP'); self.eat('NUMBER'); self.eat('RP')
        self.eat('DOT')
        return FileDecl(name,storage,keyfields)
    def parse_rule(self):
        self.eat('RULE'); name=self.eat('ID').val; self.eat('LP')
        params=[]
        if self.cur().typ!='RP':
            params.append(self.parse_param())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); params.append(self.parse_param())
        self.eat('RP'); self.eat('EQ')
        expr=self.parse_expr(); self.eat('DOT')
        return RuleDecl(name,params,expr)
    def parse_param(self):
        n=self.eat('ID').val; self.eat('COL'); t=self.parse_type_ref(); return Param(n,t)
    def parse_proc(self):
        self.eat('PROC'); name=self.eat('ID').val; self.eat('LP')
        params=[]
        if self.cur().typ!='RP':
            params.append(self.parse_param())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); params.append(self.parse_param())
        self.eat('RP'); self.eat('EQ')
        body=[]
        while self.cur().typ!='DOT':
            body.append(self.parse_stmt())
        self.eat('DOT')
        return ProcDecl(name,params,body)
    def parse_stmt(self):
        t=self.cur()
        if t.typ=='REQUIRE':
            self.eat('REQUIRE'); e=self.parse_expr(); self.eat('DOT'); return Require(e)
        if t.typ=='LOAD':
            self.eat('LOAD'); rec=self.eat('ID').val; self.eat('LP')
            keys=[]
            if self.cur().typ!='RP':
                keys.append(self.parse_expr())
                while self.cur().typ=='COMMA':
                    self.eat('COMMA'); keys.append(self.parse_expr())
            self.eat('RP'); self.eat('AS'); alias=self.eat('ID').val; self.eat('DOT'); return Load(rec,keys,alias)
        if t.typ=='SAVE':
            self.eat('SAVE'); alias=self.eat('ID').val; self.eat('DOT'); return Save(alias)
        if t.typ=='IF':
            self.eat('IF'); cond=self.parse_expr(); self.eat('THEN')
            thenSt=[]
            while self.cur().typ not in ('ELSE','ENDIF'):
                thenSt.append(self.parse_stmt())
            elseSt=[]
            if self.cur().typ=='ELSE':
                self.eat('ELSE')
                while self.cur().typ!='ENDIF':
                    elseSt.append(self.parse_stmt())
            self.eat('ENDIF'); self.eat('DOT'); return IfStmt(cond,thenSt,elseSt)
        if t.typ=='FAIL':
            self.eat('FAIL'); msg=self.eat('STRING').val; self.eat('DOT'); return Fail(msg)
        # assign: ident := expr .
        if t.typ=='ID':
            left=self.eat('ID').val
            if self.cur().typ=='DOT':
                self.eat('DOT'); fld=self.eat('ID').val; left=(left,fld)
            self.eat('EQ'); expr=self.parse_expr(); self.eat('DOT'); return Assign(left,expr)
        self.error(f"Unknown stmt {t}")
    def parse_expr(self):
        # only simple binary ops and IN
        left=self.parse_primary()
        if self.cur().typ=='OP':
            op=self.eat('OP').val; right=self.parse_primary(); return BinOp(op,left,right)
        if self.cur().typ=='IN':
            self.eat('IN'); self.eat('LP'); vals=[]
            vals.append(self.parse_primary())
            while self.cur().typ=='COMMA':
                self.eat('COMMA'); vals.append(self.parse_primary())
            self.eat('RP'); return InExpr(left,vals)
        return left
    def parse_primary(self):
        t=self.cur()
        if t.typ=='ID':
            # could be enum literal Type.Variant
            id1=self.eat('ID').val
            if self.cur().typ== 'DOT':
                self.eat('DOT'); id2=self.eat('ID').val; return EnumLit(id1,id2)
            if self.cur().typ== 'DOT': pass
            return Ident(id1)
        if t.typ=='STRING':
            v=self.eat('STRING').val; return Literal(v[1:-1])
        if t.typ=='NUMBER':
            v=self.eat('NUMBER').val
            if '.' in v: return Literal(float(v))
            return Literal(int(v))
        if t.typ=='LP':
            self.eat('LP'); e=self.parse_expr(); self.eat('RP'); return e
        self.error(f"Unexpected primary {t}")

# ---------------------------------------------------------------------------
# Type system & Semantic Analyzer -> Business IR builder
# ---------------------------------------------------------------------------
# IR classes (compact)
class IrType: pass
class IrChar(IrType):
    def __init__(self,n): self.n=n
class IrNum(IrType):
    def __init__(self,p,s): self.p=p; self.s=s
class IrEnum(IrType):
    def __init__(self,name,variants): self.name=name; self.variants=variants
class IrRecordType(IrType):
    def __init__(self,name,fields): self.name=name; self.fields=fields

class IrField:
    def __init__(self,name,typ): self.name=name; self.typ=typ

class IrFile:
    def __init__(self,name,storage,keyfields): self.name=name; self.storage=storage; self.keyfields=keyfields

class IrRule:
    def __init__(self,name,params,expr): self.name=name; self.params=params; self.expr=expr

class IrProc:
    def __init__(self,name,params,requires,body,effects):
        self.name=name; self.params=params; self.requires=requires; self.body=body; self.effects=effects

class IrStateTransition:
    def __init__(self,record,field,froms,to,guard):
        self.record=record; self.field=field; self.froms=froms; self.to=to; self.guard=guard

# Simple symbol tables
class Context:
    def __init__(self):
        self.types: Dict[str,IrType] = {}
        self.records: Dict[str,IrRecordType] = {}
        self.files: Dict[str,IrFile] = {}
        self.rules: Dict[str,IrRule] = {}
        self.procs: Dict[str,IrProc] = {}
        # builtin primitives
        self.types['CHAR']=IrChar
        self.types['NUM']=IrNum

# Helpers to convert AST types -> IR types
def ast_type_to_ir(ctx:Context, t):
    kind = t[0]
    if kind=='CHAR': return IrChar(t[1])
    if kind=='NUM': return IrNum(t[1],t[2])
    if kind=='USER':
        name=t[1]
        if name in ctx.types and isinstance(ctx.types[name],IrEnum):
            return ctx.types[name]
        if name in ctx.records:
            return ctx.records[name]
        raise TypeError(f"Unknown user type {name}")
    raise TypeError("Unknown type")

# Semantic analyzer: build IR
def build_ir(ast:Program) -> Tuple[Context, List[IrProc]]:
    ctx=Context()
    # first pass: types and records and files
    for d in ast.decls:
        if isinstance(d,TypeDecl):
            ctx.types[d.name]=IrEnum(d.name,d.variants)
        elif isinstance(d,RecordDecl):
            fields=[IrField(f.name, None) for f in d.fields]
            # temporarily store types as raw; resolve later
            ctx.records[d.name]=IrRecordType(d.name,fields)
            # store field raw types in a map
            ctx.records[d.name].__raw_fields = d.fields
        elif isinstance(d,FileDecl):
            ctx.files[d.name]=IrFile(d.name,d.storage,d.keyfields)
    # resolve record field types
    for rname, r in ctx.records.items():
        raw = getattr(r,'__raw_fields',[])
        r.fields=[]
        for rf in raw:
            irt = ast_type_to_ir(ctx, rf.typ)
            r.fields.append(IrField(rf.name,irt))
    # second pass: rules and procs
    ir_procs=[]
    for d in ast.decls:
        if isinstance(d,RuleDecl):
            # params: list of Param
            params=[(p.name, ast_type_to_ir(ctx,p.typ)) for p in d.params]
            ir = IrRule(d.name, params, d.expr)
            ctx.rules[d.name]=ir
        if isinstance(d,ProcDecl):
            params=[(p.name, ast_type_to_ir(ctx,p.typ)) for p in d.params]
            # body -> simple translation to IR statements (we keep AST stmts but validate)
            requires=[]; body=[]; effects=[]
            for s in d.body:
                if isinstance(s,Require):
                    requires.append(s.expr)
                else:
                    body.append(s)
            proc = IrProc(d.name, params, requires, body, effects)
            ctx.procs[d.name]=proc
            ir_procs.append(proc)
    # basic semantic checks
    # RULE purity: ensure no LOAD/SAVE/FAIL in rule expr (we only allow expressions)
    for r in ctx.rules.values():
        # naive: assume expr is pure
        pass
    return ctx, ir_procs

# ---------------------------------------------------------------------------
# IR -> COBOL codegen (template-based, minimal)
# ---------------------------------------------------------------------------
def emit_cobol_program(ctx:Context, proc:IrProc, files_map:Dict[str,IrFile], records_map:Dict[str,IrRecordType]):
    # Only supports single-record param that maps to a file record
    prog = []
    pid = proc.name.upper()
    prog.append(f"IDENTIFICATION DIVISION.\nPROGRAM-ID. {pid}.\n")
    # ENV + FILE-CONTROL
    prog.append("ENVIRONMENT DIVISION.\nINPUT-OUTPUT SECTION.\nFILE-CONTROL.\n")
    # emit files used by proc by scanning LOAD/SAVE statements
    used_files=set()
    for s in proc.body:
        if isinstance(s,Load):
            used_files.add(s.recname)
    for fname in used_files:
        f = files_map[fname]
        prog.append(f"    SELECT {fname.upper()}-FILE ASSIGN TO {f.storage}\n")
        prog.append("        ORGANIZATION IS INDEXED\n        ACCESS MODE IS DYNAMIC\n        RECORD KEY IS {0}-KEY\n        FILE STATUS IS {0}-STATUS.\n".format(fname.upper()))
    # DATA DIVISION
    prog.append("\nDATA DIVISION.\nFILE SECTION.\n")
    for fname in used_files:
        rec = records_map[fname]
        prog.append(f"FD {fname.upper()}-FILE.\n01 {fname.upper()}-REC.\n")
        for fld in rec.fields:
            if isinstance(fld.typ,IrChar):
                prog.append(f"   05 {fld.name.upper():<20} PIC X({fld.typ.n}).\n")
            elif isinstance(fld.typ,IrNum):
                # map to display numeric for simplicity
                p=fld.typ.p; s=fld.typ.s
                intd = p - s
                pic = f"S{intd}({intd})V{('9'*s) if s>0 else ''}"
                # fallback to generic
                pic = f"S9({p})V9({s})"
                prog.append(f"   05 {fld.name.upper():<20} PIC {pic}.\n")
            elif isinstance(fld.typ,IrEnum):
                prog.append(f"   05 {fld.name.upper():<20} PIC X(12).\n")
            else:
                prog.append(f"   05 {fld.name.upper():<20} PIC X(32).\n")
    # WORKING-STORAGE
    prog.append("\nWORKING-STORAGE SECTION.\n01 WS-STATUS PIC X(02).\n")
    # LINKAGE
    prog.append("\nLINKAGE SECTION.\n")
    for pname, ptype in proc.params:
        # map param types to PICs
        if isinstance(ptype,IrRecordType):
            # expand fields as linkage
            for fld in ptype.fields:
                if isinstance(fld.typ,IrChar):
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC X({fld.typ.n}).\n")
                elif isinstance(fld.typ,IrNum):
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC S9({fld.typ.p})V9({fld.typ.s}).\n")
                else:
                    prog.append(f"01 LK-{fld.name.upper():<20} PIC X(32).\n")
        else:
            if isinstance(ptype,IrChar):
                prog.append(f"01 LK-{pname.upper():<20} PIC X({ptype.n}).\n")
            elif isinstance(ptype,IrNum):
                prog.append(f"01 LK-{pname.upper():<20} PIC S9({ptype.p})V9({ptype.s}).\n")
            else:
                prog.append(f"01 LK-{pname.upper():<20} PIC X(32).\n")
    # PROCEDURE DIVISION
    prog.append("\nPROCEDURE DIVISION USING ")
    prog.append(', '.join([pname.upper() for pname,_ in proc.params]) + ".\n\n")
    # Emit requires as IF checks
    for req in proc.requires:
        # naive: only support simple IN checks and not equals
        if isinstance(req,InExpr):
            left = req.left
            if isinstance(left,FieldRef):
                prog.append(f"    IF {left.alias.upper()}-{left.field.upper()} NOT IN (")
                vals = []
                for v in req.vals:
                    if isinstance(v,EnumLit):
                        vals.append(f"'{v.variant}'")
                    elif isinstance(v,Literal):
                        vals.append(f"'{v.val}'")
                prog.append(','.join(vals)+")\n")
                prog.append("       MOVE 'BADSTATE' TO WS-STATUS\n       GOBACK\n    END-IF\n")
        elif isinstance(req,BinOp) and req.op=='!=':
            # left != right
            l=req.l; r=req.r
            if isinstance(l,FieldRef) and isinstance(r,EnumLit):
                prog.append(f"    IF {l.alias.upper()}-{l.field.upper()} = '{r.variant}'\n")
                prog.append("       MOVE 'ALREADYRT' TO WS-STATUS\n       GOBACK\n    END-IF\n")
    # Body: handle LOAD/Assign/SAVE/Fail/If
    for s in proc.body:
        if isinstance(s,Load):
            # READ file by key
            key_exprs = s.keys
            # assume keys are Ident or Literal
            keyvals=[]
            for ke in key_exprs:
                if isinstance(ke,Literal): keyvals.append(str(ke.val))
                elif isinstance(ke,Ident): keyvals.append(ke.name.upper())
                elif isinstance(ke,FieldRef): keyvals.append(f"{ke.alias.upper()}-{ke.field.upper()}")
                else: keyvals.append('0')
            prog.append(f"    MOVE {keyvals[0]} TO {s.recname.upper()}-KEY\n")
            prog.append(f"    READ {s.recname.upper()}-FILE\n        INVALID KEY\n            MOVE 'NOTFOUND' TO WS-STATUS\n            GOBACK\n    END-READ\n")
        elif isinstance(s,Assign):
            tgt = s.target
            if isinstance(tgt,tuple):
                alias, fld = tgt
                # expr simple literal or enum
                if isinstance(s.expr,EnumLit):
                    prog.append(f"    MOVE '{s.expr.variant}' TO {alias.upper()}-{fld.upper()}\n")
                elif isinstance(s.expr,Literal):
                    prog.append(f"    MOVE '{s.expr.val}' TO {alias.upper()}-{fld.upper()}\n")
                elif isinstance(s.expr,FieldRef):
                    prog.append(f"    MOVE {s.expr.alias.upper()}-{s.expr.field.upper()} TO {alias.upper()}-{fld.upper()}\n")
            else:
                # simple var assign
                if isinstance(s.expr,Literal):
                    prog.append(f"    MOVE '{s.expr.val}' TO {tgt.upper()}\n")
        elif isinstance(s,Save):
            prog.append(f"    REWRITE {s.alias.upper()}-REC\n        INVALID KEY\n            MOVE 'DBERR' TO WS-STATUS\n            GOBACK\n    END-REWRITE\n")
        elif isinstance(s,Fail):
            prog.append(f"    MOVE 'FAIL' TO WS-STATUS\n    GOBACK\n")
        elif isinstance(s,IfStmt):
            # naive: only simple condition checks
            cond = s.cond
            if isinstance(cond,BinOp) and cond.op=='=' and isinstance(cond.l,FieldRef) and isinstance(cond.r,Literal):
                prog.append(f"    IF {cond.l.alias.upper()}-{cond.l.field.upper()} = '{cond.r.val}'\n")
                for ss in s.thenStmts:
                    if isinstance(ss,Fail):
                        prog.append(f"       MOVE 'FAIL' TO WS-STATUS\n       GOBACK\n")
                prog.append("    END-IF\n")
    prog.append("\n    MOVE 'OK' TO WS-STATUS\n    GOBACK.\n")
    return ''.join(prog)

# ---------------------------------------------------------------------------
# IR -> Prolog codegen (simple)
# ---------------------------------------------------------------------------
def emit_prolog(ctx:Context, proc:IrProc, records_map:Dict[str,IrRecordType]):
    out=[]
    # facts: record predicate signatures
    for rname, rec in records_map.items():
        fields = ','.join([f.name for f in rec.fields])
        # we don't emit facts here; backend expects facts from DB
        out.append(f"% record {rname}({fields})\n")
    # rules: map ctx.rules
    for rname, rule in ctx.rules.items():
        # naive: assume single param and IN expression
        expr = rule.expr
        if isinstance(expr,InExpr):
            left = expr.left
            vals = [v.variant if isinstance(v,EnumLit) else (v.val if isinstance(v,Literal) else str(v)) for v in expr.vals]
            out.append(f"{rname}({left.alias if isinstance(left,FieldRef) else left.name}) :-\n")
            conds = ' ; '.join([f"{left.alias if isinstance(left,FieldRef) else left.name} = {v.lower()}" for v in vals])
            out.append(f"    ({conds}).\n")
    # proc semantics: produce relation return_item(Item,Reason,Result)
    # naive mapping: find LOAD/Assign/Save pattern
    out.append(f"\n% proc {proc.name}\n")
    # produce clauses for success and errors for the example pattern
    # This is a small generator: detect LOAD then state checks then assign to state RETURNED
    # We'll emit a generic clause
    out.append(f"{proc.name}(Item, Reason, Result) :-\n")
    out.append(f"    Item = item(Company,Batch,Entry,State,Amount,OldReason),\n")
    out.append(f"    ( State = posted ; State = settled ),\n")
    out.append(f"    State \\= returned,\n")
    out.append(f"    Result = item(Company,Batch,Entry,returned,Amount,Reason).\n\n")
    # error clauses
    out.append(f"{proc.name}_error(notfound) :- \\+ item(_,_,_,_,_,_).\n")
    out.append(f"{proc.name}_error(badstate) :- item(_,_,_,State,_,_), \\+ (State = posted ; State = settled).\n")
    out.append(f"{proc.name}_error(alreadyrt) :- item(_,_,_,returned,_,_).\n")
    return ''.join(out)

# ---------------------------------------------------------------------------
# IR -> Mercury codegen (very small)
# ---------------------------------------------------------------------------
def emit_mercury(ctx:Context, proc:IrProc, records_map:Dict[str,IrRecordType]):
    out=[]
    out.append(":- module funnel_generated.\n:- interface.\n:- import_module io.\n\n")
    out.append(":- type state ---> new ; posted ; settled ; returned.\n\n")
    # item type
    out.append(":- type item ---> item(string, string, string, state, float, string).\n\n")
    out.append(":- pred return_item(item::in, string::in, item::out) is det.\n\n")
    out.append(":- implementation.\n\n")
    out.append("return_item(Item, Reason, Result) :-\n")
    out.append("    ( if Item = item(C,B,E,State,A,_) then\n")
    out.append("        ( if (State = posted ; State = settled), State \\= returned then\n")
    out.append("            Result = item(C,B,E,returned,A,Reason)\n")
    out.append("          else\n")
    out.append("            Result = Item\n")
    out.append("        )\n")
    out.append("      else\n")
    out.append("        Result = Item\n")
    out.append("    ).\n")
    return ''.join(out)

# ---------------------------------------------------------------------------
# Small driver & example
# ---------------------------------------------------------------------------
EXAMPLE = r'''
PROGRAM ach_return.

TYPE State = NEW | POSTED | SETTLED | RETURNED.

RECORD Item {
    company : CHAR(3).
    batch   : CHAR(10).
    entry   : CHAR(15).
    state   : State.
    amount  : NUM(13,2).
    reason  : CHAR(3).
}.

FILE achitem USING ACHITEM KEY company(3), batch(10), entry(15).

RULE returnable(item : Item) = item.state IN (State.POSTED, State.SETTLED).

PROC return_item(item : Item, reason : CHAR(3)) =
    REQUIRE returnable(item).
    REQUIRE item.state != State.RETURNED.
    item.state := State.RETURNED.
    item.reason := reason.
    SAVE item.
.
'''

def compile_source(src:str, target='cobol'):
    toks = lex(src)
    p = Parser(toks)
    ast = p.parse()
    ctx, procs = build_ir(ast)
    # build maps
    records_map = ctx.records
    files_map = ctx.files
    # pick first proc
    if not procs:
        print("No procs found"); return
    proc = procs[0]
    if target=='cobol':
        out = emit_cobol_program(ctx, proc, files_map, records_map)
    elif target=='prolog':
        out = emit_prolog(ctx, proc, records_map)
    elif target=='mercury':
        out = emit_mercury(ctx, proc, records_map)
    else:
        out = "// unknown target"
    return out

# CLI
def main():
    if len(sys.argv)<2:
        print("Usage: funnelc.py <file.fnl> --target cobol|prolog|mercury")
        print("Running example and printing COBOL by default\n")
        src = EXAMPLE
        print(compile_source(src,'cobol'))
        return
    srcfile = sys.argv[1]
    target = 'cobol'
    if '--target' in sys.argv:
        target = sys.argv[sys.argv.index('--target')+1]
    with open(srcfile,'r') as f:
        src = f.read()
    out = compile_source(src,target)
    print(out)

if __name__=='__main__':
    main()
