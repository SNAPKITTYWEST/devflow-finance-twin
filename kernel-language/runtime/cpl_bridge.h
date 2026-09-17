#ifndef CPL_BRIDGE_H
#define CPL_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t cpl_word;
typedef uint64_t cpl_addr;
typedef int32_t cpl_pred;

typedef struct {
    cpl_addr entry;
    int n_regs;
    int n_preds;
    int shared_bytes;
    int priority;
    int deadline;
    const char *name;
    void *ml_annot;
} cpl_kernel_t;

typedef enum {
    CPL_MEM_HOST = 0,
    CPL_MEM_DEVICE,
    CPL_MEM_SHARED,
    CPL_MEM_CONSTANT,
    CPL_MEM_ABSOLUTE
} cpl_memspace_t;

typedef struct {
    void *host_ptr;
    cpl_addr device_ptr;
    size_t bytes;
    cpl_memspace_t space;
    int registered;
} cpl_buffer_t;

typedef enum {
    CPL_OK = 0,
    CPL_ERR_NOMEM,
    CPL_ERR_INVALID,
    CPL_ERR_DEVICE,
    CPL_ERR_TIMEOUT,
    CPL_ERR_NOTIMPL
} cpl_status_t;

cpl_status_t cpl_init(int device_id);
void cpl_shutdown(void);

cpl_status_t cpl_buffer_alloc(cpl_buffer_t *b, size_t bytes, cpl_memspace_t sp);
cpl_status_t cpl_buffer_free(cpl_buffer_t *b);
cpl_status_t cpl_buffer_upload(cpl_buffer_t *b, const void *src, size_t n);
cpl_status_t cpl_buffer_download(cpl_buffer_t *b, void *dst, size_t n);

cpl_status_t cpl_kernel_register(cpl_kernel_t *k,
                                 const void *sass_image, size_t image_bytes,
                                 const char *name);
cpl_status_t cpl_kernel_set_annot(cpl_kernel_t *k, void *ml_annot);
cpl_status_t cpl_kernel_set_priority(cpl_kernel_t *k, int prio);
cpl_status_t cpl_kernel_set_deadline(cpl_kernel_t *k, int deadline_us);

typedef struct {
    int grid_x, grid_y, grid_z;
    int block_x, block_y, block_z;
    int shared_dynamic;
} cpl_launch_t;

cpl_status_t cpl_launch(cpl_kernel_t *k, const cpl_launch_t *cfg,
                        cpl_buffer_t **args, int nargs);

cpl_status_t cpl_device_sync(void);
cpl_status_t cpl_stream_sync(void *stream);

const char *cpl_status_string(cpl_status_t s);
void cpl_print_kernel(const cpl_kernel_t *k);

#ifdef __cplusplus
}
#endif

#endif /* CPL_BRIDGE_H */
