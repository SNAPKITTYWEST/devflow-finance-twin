#include "cpl_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int cpl_initialized = 0;
static int cpl_device = -1;

const char *cpl_status_string(cpl_status_t s) {
    switch (s) {
    case CPL_OK: return "OK";
    case CPL_ERR_NOMEM: return "NOMEM";
    case CPL_ERR_INVALID: return "INVALID";
    case CPL_ERR_DEVICE: return "DEVICE";
    case CPL_ERR_TIMEOUT: return "TIMEOUT";
    case CPL_ERR_NOTIMPL: return "NOTIMPL";
    default: return "?";
    }
}

cpl_status_t cpl_init(int device_id) {
    if (cpl_initialized) return CPL_OK;
    cpl_device = device_id;
    cpl_initialized = 1;
    return CPL_OK;
}

void cpl_shutdown(void) {
    cpl_initialized = 0;
    cpl_device = -1;
}

cpl_status_t cpl_buffer_alloc(cpl_buffer_t *b, size_t bytes, cpl_memspace_t sp) {
    if (!b || bytes == 0) return CPL_ERR_INVALID;
    memset(b, 0, sizeof(*b));
    b->bytes = bytes;
    b->space = sp;
    if (sp == CPL_MEM_HOST || sp == CPL_MEM_ABSOLUTE) {
        b->host_ptr = malloc(bytes);
        if (!b->host_ptr) return CPL_ERR_NOMEM;
        memset(b->host_ptr, 0, bytes);
    } else {
        b->device_ptr = 0;
        b->host_ptr = malloc(bytes);
        if (!b->host_ptr) return CPL_ERR_NOMEM;
    }
    b->registered = 1;
    return CPL_OK;
}

cpl_status_t cpl_buffer_free(cpl_buffer_t *b) {
    if (!b || !b->registered) return CPL_ERR_INVALID;
    free(b->host_ptr);
    b->host_ptr = NULL;
    b->device_ptr = 0;
    b->registered = 0;
    return CPL_OK;
}

cpl_status_t cpl_buffer_upload(cpl_buffer_t *b, const void *src, size_t n) {
    if (!b || !b->registered || !src) return CPL_ERR_INVALID;
    if (n > b->bytes) n = b->bytes;
    memcpy(b->host_ptr, src, n);
    return CPL_OK;
}

cpl_status_t cpl_buffer_download(cpl_buffer_t *b, void *dst, size_t n) {
    if (!b || !b->registered || !dst) return CPL_ERR_INVALID;
    if (n > b->bytes) n = b->bytes;
    memcpy(dst, b->host_ptr, n);
    return CPL_OK;
}

cpl_status_t cpl_kernel_register(cpl_kernel_t *k,
                                 const void *sass_image, size_t image_bytes,
                                 const char *name) {
    if (!k) return CPL_ERR_INVALID;
    memset(k, 0, sizeof(*k));
    k->name = name ? name : "anon";
    k->entry = (cpl_addr)(uintptr_t)sass_image;
    k->n_regs = 32;
    k->n_preds = 4;
    k->shared_bytes = 0;
    k->priority = 0;
    k->deadline = 0;
    (void)image_bytes;
    return CPL_OK;
}

cpl_status_t cpl_kernel_set_annot(cpl_kernel_t *k, void *ml_annot) {
    if (!k) return CPL_ERR_INVALID;
    k->ml_annot = ml_annot;
    return CPL_OK;
}

cpl_status_t cpl_kernel_set_priority(cpl_kernel_t *k, int prio) {
    if (!k) return CPL_ERR_INVALID;
    k->priority = prio;
    return CPL_OK;
}

cpl_status_t cpl_kernel_set_deadline(cpl_kernel_t *k, int deadline_us) {
    if (!k) return CPL_ERR_INVALID;
    k->deadline = deadline_us;
    return CPL_OK;
}

cpl_status_t cpl_launch(cpl_kernel_t *k, const cpl_launch_t *cfg,
                        cpl_buffer_t **args, int nargs) {
    if (!k || !cfg) return CPL_ERR_INVALID;
    if (!cpl_initialized) return CPL_ERR_DEVICE;

    fprintf(stderr, "[cpl] launch %s grid=(%d,%d,%d) block=(%d,%d,%d) args=%d\n",
            k->name ? k->name : "?",
            cfg->grid_x, cfg->grid_y, cfg->grid_z,
            cfg->block_x, cfg->block_y, cfg->block_z,
            nargs);

    /* In a real system: cuLaunchKernel or custom command buffer */
    (void)args;
    return CPL_OK;
}

cpl_status_t cpl_device_sync(void) {
    if (!cpl_initialized) return CPL_ERR_DEVICE;
    return CPL_OK;
}

cpl_status_t cpl_stream_sync(void *stream) {
    if (!cpl_initialized) return CPL_ERR_DEVICE;
    (void)stream;
    return CPL_OK;
}

void cpl_print_kernel(const cpl_kernel_t *k) {
    if (!k) return;
    fprintf(stderr, "[cpl] kernel: %s  regs=%d  preds=%d  shared=%d  prio=%d  dl=%d\n",
            k->name ? k->name : "?",
            k->n_regs, k->n_preds, k->shared_bytes,
            k->priority, k->deadline);
}
