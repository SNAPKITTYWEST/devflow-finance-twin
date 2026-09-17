/* Minimal Smalltalk-80 inspired object runtime - dense hand-rolled.
   Used only for thick annotation objects and host-side metadata;
   the KERNEL LANGUAGE itself stays BLISS/PLM/CORAL.
   No GC in the device path. Systems style. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define ST_MAX_OBJECTS 512
#define ST_MAX_SLOTS 32
#define ST_MAX_METHODS 64
#define ST_MAX_CLASSES 32

typedef struct STObject STObject;
typedef struct STClass STClass;
typedef struct STMethod STMethod;

struct STMethod {
    char name[32];
    STObject *(*fn)(STObject *self, STObject **args, int argc);
};

struct STClass {
    char name[32];
    STClass *super;
    STMethod methods[ST_MAX_METHODS];
    int n_methods;
    int n_inst_vars;
};

struct STObject {
    STClass *class;
    STObject *slots[ST_MAX_SLOTS];
    int64_t ival;
    char *bytes;
    int size;
};

static STClass classes[ST_MAX_CLASSES];
static int n_classes = 0;
static STObject objects[ST_MAX_OBJECTS];
static int n_objects = 0;

STClass *st_class(const char *name, STClass *super, int n_ivars) {
    if (n_classes >= ST_MAX_CLASSES) return NULL;
    STClass *c = &classes[n_classes++];
    memset(c, 0, sizeof(*c));
    strncpy(c->name, name, 31);
    c->super = super;
    c->n_inst_vars = n_ivars;
    return c;
}

void st_add_method(STClass *c, const char *name,
                   STObject *(*fn)(STObject *, STObject **, int)) {
    if (c->n_methods >= ST_MAX_METHODS) return;
    STMethod *m = &c->methods[c->n_methods++];
    strncpy(m->name, name, 31);
    m->fn = fn;
}

STObject *st_new(STClass *c) {
    if (n_objects >= ST_MAX_OBJECTS) return NULL;
    STObject *o = &objects[n_objects++];
    memset(o, 0, sizeof(*o));
    o->class = c;
    return o;
}

STObject *st_integer(int64_t v) {
    STObject *o = st_new(NULL);
    o->ival = v;
    return o;
}

STObject *st_send(STObject *self, const char *selector,
                  STObject **args, int argc) {
    if (!self || !self->class) return NULL;
    for (STClass *c = self->class; c; c = c->super) {
        for (int i = 0; i < c->n_methods; i++) {
            if (strcmp(c->methods[i].name, selector) == 0)
                return c->methods[i].fn(self, args, argc);
        }
    }
    fprintf(stderr, "doesNotUnderstand: %s\n", selector);
    return NULL;
}

static STObject *annot_set_priority(STObject *self, STObject **args, int argc) {
    if (argc >= 1) self->slots[0] = args[0];
    return self;
}
static STObject *annot_set_deadline(STObject *self, STObject **args, int argc) {
    if (argc >= 1) self->slots[1] = args[0];
    return self;
}
static STObject *annot_priority(STObject *self, STObject **args, int argc) {
    (void)args; (void)argc;
    return self->slots[0] ? self->slots[0] : st_integer(0);
}
static STObject *annot_deadline(STObject *self, STObject **args, int argc) {
    (void)args; (void)argc;
    return self->slots[1] ? self->slots[1] : st_integer(0);
}

STClass *st_AnnotationClass;

void st_boot(void) {
    st_AnnotationClass = st_class("Annotation", NULL, 4);
    st_add_method(st_AnnotationClass, "priority:", annot_set_priority);
    st_add_method(st_AnnotationClass, "deadline:", annot_set_deadline);
    st_add_method(st_AnnotationClass, "priority", annot_priority);
    st_add_method(st_AnnotationClass, "deadline", annot_deadline);
}

STObject *st_new_annotation(int priority, int deadline) {
    STObject *a = st_new(st_AnnotationClass);
    STObject *p = st_integer(priority);
    STObject *d = st_integer(deadline);
    st_send(a, "priority:", &p, 1);
    st_send(a, "deadline:", &d, 1);
    return a;
}

#ifdef ST80_MAIN
int main(void) {
    st_boot();
    STObject *a = st_new_annotation(5, 1000);
    STObject *p = st_send(a, "priority", NULL, 0);
    STObject *d = st_send(a, "deadline", NULL, 0);
    printf("annotation: priority=%ld deadline=%ld\n",
           p ? p->ival : -1, d ? d->ival : -1);
    return 0;
}
#endif
