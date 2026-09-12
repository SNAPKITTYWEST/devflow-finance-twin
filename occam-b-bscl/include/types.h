/* in include/types.h, replace:
   struct Node;
   struct DiagList;
   ... typecheck_program(struct Node *prog, FuncTab *ft, struct DiagList *dg, ...)
   with: */
#include "diagnostics.h"
struct Node;
bool typecheck_program(struct Node *prog, FuncTab *ft, DiagList *dg,
                       const char *file);
