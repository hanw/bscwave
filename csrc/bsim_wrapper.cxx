// Generic bsim_* shim over the Bluesim bk_* kernel API.
// Compile alongside each design's bsc-generated objects to produce libsim.so.
//
// Lookup convention: port/state names are paths through the bsc symbol table,
// rooted at the kernel's top symbol. The top module instance is "top" by bsc
// convention, so e.g. an Action method "incr" is reached as "top.EN_incr" and
// a Reg named "count" as "top.count" (which resolves to the register module's
// inner value symbol).
//
// Model factories are resolved via dlsym(RTLD_DEFAULT, "new_MODEL_<name>"),
// so any bsc-generated sim.so loaded into the same address space works.

#include "bluesim_kernel_api.h"
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <dlfcn.h>

extern "C" {

struct Handle {
  void* model;
  tSimStateHdl sim;
  tClock clk;
};

// Resolve a value symbol. If the path lands on a module (e.g. a Reg primitive),
// descend into its first sub-symbol, which by bsc convention holds the value.
static tSymbol lookup_value(tSimStateHdl sim, const char* name) {
  tSymbol sym = bk_lookup_symbol(bk_top_symbol(sim), name);
  if (sym == BAD_SYMBOL) return BAD_SYMBOL;
  if (bk_is_module(sym) && bk_num_symbols(sym) > 0) {
    sym = bk_get_nth_symbol(sym, 0);
  }
  return sym;
}

void* bsim_create(const char* model_name) {
  char sym_name[256];
  std::snprintf(sym_name, sizeof(sym_name), "new_MODEL_%s", model_name);
  typedef void* (*Factory)();
  Factory factory = reinterpret_cast<Factory>(dlsym(RTLD_DEFAULT, sym_name));
  if (!factory) return nullptr;
  void* model = factory();
  tSimStateHdl sim = bk_init(static_cast<tModel>(model), false);
  Handle* h = new Handle{model, sim, bk_get_clock_by_name(sim, "CLK")};
  bk_use_default_reset(sim);
  bk_trigger_clock_edge(sim, h->clk, POSEDGE, 1);
  bk_schedule_ui_event(sim, 3);
  bk_advance(sim, false);
  return h;
}

void bsim_destroy(void* p) {
  Handle* h = static_cast<Handle*>(p);
  bk_shutdown(h->sim);
  delete h;
}

void bsim_clock_posedge(void* p, const char* /*clk_name*/) {
  Handle* h = static_cast<Handle*>(p);
  tTime t = bk_now(h->sim) + 1;
  bk_trigger_clock_edge(h->sim, h->clk, POSEDGE, t);
  bk_schedule_ui_event(h->sim, t);
  bk_advance(h->sim, false);
}

void bsim_clock_negedge(void* p, const char* /*clk_name*/) {
  Handle* h = static_cast<Handle*>(p);
  tTime t = bk_now(h->sim) + 1;
  bk_trigger_clock_edge(h->sim, h->clk, NEGEDGE, t);
  bk_schedule_ui_event(h->sim, t);
  bk_advance(h->sim, false);
}

int bsim_set_param(void* p, const char* name, const uint32_t* words, int /*nwords*/) {
  Handle* h = static_cast<Handle*>(p);
  tSymbol sym = lookup_value(h->sim, name);
  if (sym == BAD_SYMBOL) return -1;
  void* ptr = bk_get_ptr(sym);
  if (!ptr) return -1;
  uint32_t bits = bk_get_size(sym);
  if (bits <= 8) {
    uint32_t mask = (bits == 8) ? 0xFFu : ((1u << bits) - 1);
    *static_cast<uint8_t*>(ptr) = static_cast<uint8_t>(words[0] & mask);
  } else if (bits <= 32) {
    uint32_t mask = (bits == 32) ? 0xFFFFFFFFu : ((1u << bits) - 1);
    *static_cast<uint32_t*>(ptr) = words[0] & mask;
  } else if (bits <= 64) {
    *static_cast<uint64_t*>(ptr) =
      static_cast<uint64_t>(words[0]) | (static_cast<uint64_t>(words[1]) << 32);
  } else {
    std::memcpy(ptr, words, ((bits + 31) / 32) * 4);
  }
  return 0;
}

int bsim_get_result(void* p, const char* name, uint32_t* words, int nwords) {
  Handle* h = static_cast<Handle*>(p);
  tSymbol sym = lookup_value(h->sim, name);
  if (sym == BAD_SYMBOL) return -1;
  void* ptr = bk_get_ptr(sym);
  if (!ptr) return -1;
  uint32_t bits = bk_get_size(sym);
  if (bits <= 8) {
    words[0] = *static_cast<uint8_t*>(ptr);
  } else if (bits <= 32) {
    words[0] = *static_cast<uint32_t*>(ptr);
  } else if (bits <= 64) {
    uint64_t v = *static_cast<uint64_t*>(ptr);
    words[0] = static_cast<uint32_t>(v);
    if (nwords > 1) words[1] = static_cast<uint32_t>(v >> 32);
  } else {
    std::memcpy(words, ptr, ((bits + 31) / 32) * 4);
  }
  return 0;
}

} // extern "C"
