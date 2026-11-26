#include "my_application.h"

#ifdef __GLIBC__
#include <malloc.h>
#endif

#ifdef __GLIBC__
// glibc's malloc, which the Rust core, SQLite and the engine allocate from, gives each busy
// thread its own pool (up to 8 per core: 96 pools on a 16-core laptop) and keeps what is
// freed in it. Over a day of use OxiTalk held ~950 MB of heap with only ~165 MB in use; the
// rest sat in idle pools and went to swap. Fewer pools share their free memory, large blocks
// go straight back to the system when freed, and a periodic trim returns the free pages.
static constexpr int kMallocPools = 4;
static constexpr int kLargeBlockBytes = 256 * 1024;
static constexpr guint kTrimEverySeconds = 120;

static gboolean trim_heap(gpointer user_data) {
  malloc_trim(0);
  return G_SOURCE_CONTINUE;
}

// Before any thread starts, so every thread uses the shared pools.
static void tune_malloc() {
  mallopt(M_ARENA_MAX, kMallocPools);
  // Fixed, so glibc doesn't raise it after a large block is freed (which keeps later large
  // blocks, such as decrypted pictures, in the pools).
  mallopt(M_MMAP_THRESHOLD, kLargeBlockBytes);
  mallopt(M_TRIM_THRESHOLD, 2 * kLargeBlockBytes);
}
#endif

int main(int argc, char** argv) {
#ifdef __GLIBC__
  tune_malloc();
  g_timeout_add_seconds(kTrimEverySeconds, trim_heap, nullptr);
#endif
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
