#ifndef KERNEL_CODEGEN_H
#define KERNEL_CODEGEN_H

#include "ast.h"
#include "ir.h"

IrModule *codegen(AstNode *module);

#endif
