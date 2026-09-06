// Native (host) unit test for the pure dashboard-command classifier — SmCommand.h.
//
// Zero Arduino/Serial/NVS dependencies, so it compiles + runs on any host toolchain:
//   c++ -std=c++17 -I ../../bootgate test_sm_command.cpp -o t && ./t   # exit 0 == all pass
// It is also `-fsyntax-only`-checked under the ESP32 cross toolchain in CI / the build harness.
//
// This locks in the W1 wipe-misfire fix (audit DEADMANS-AUDIT-2026-07-12 §GateInput_serial.cpp:313):
// the SINGLE safety invariant is that ONLY a clean `sm_wipe` ever maps to WipeRequest — a typo, an
// unknown/future command, or a mangled keyword must classify as Unknown and never reach the wipe path.
#include <cassert>

#include "SmCommand.h"

using suicide::dashboard::SmCommand;
using suicide::dashboard::SmDispatch;
using suicide::dashboard::classifySmCommand;
using suicide::dashboard::smDispatch;

int main() {
  // --- recognized commands (exact token: keyword + end-of-string or a space) ---
  assert(classifySmCommand("sm_status") == SmCommand::Status);
  assert(classifySmCommand("sm_info") == SmCommand::Info);
  assert(classifySmCommand("sm_arm") == SmCommand::Arm);
  assert(classifySmCommand("sm_disarm") == SmCommand::Disarm);
  assert(classifySmCommand("sm_set_password") == SmCommand::SetPassword);
  assert(classifySmCommand("sm_wipe") == SmCommand::Wipe);

  // case-insensitive (commands may arrive upper/mixed case)
  assert(classifySmCommand("SM_STATUS") == SmCommand::Status);
  assert(classifySmCommand("Sm_Wipe") == SmCommand::Wipe);

  // a trailing space (with or without args) is still the same command
  assert(classifySmCommand("sm_status ") == SmCommand::Status);
  assert(classifySmCommand("sm_wipe ") == SmCommand::Wipe);
  assert(classifySmCommand("sm_wipe now") == SmCommand::Wipe);

  // --- the misfire cases: these used to be routed into the authenticated wipe prompt ---
  assert(classifySmCommand("sm_wipex") == SmCommand::Unknown);   // extra byte -> NOT wipe
  assert(classifySmCommand("sm_wipe\t") == SmCommand::Unknown);  // tab-mangled -> NOT wipe
  assert(classifySmCommand("sm_reboot") == SmCommand::Unknown);  // unknown/future command
  assert(classifySmCommand("sm_stat") == SmCommand::Unknown);    // truncated typo
  assert(classifySmCommand("sm_statusx") == SmCommand::Unknown); // trailing byte on a known keyword
  assert(classifySmCommand("sm_") == SmCommand::Unknown);        // bare prefix
  assert(classifySmCommand("sm_ wipe") == SmCommand::Unknown);   // space before the keyword

  // --- dispatch mapping: ONLY Wipe -> WipeRequest ---
  assert(smDispatch(SmCommand::Wipe) == SmDispatch::WipeRequest);
  assert(smDispatch(SmCommand::Unknown) == SmDispatch::Unknown);
  assert(smDispatch(SmCommand::Status) == SmDispatch::Handled);
  assert(smDispatch(SmCommand::Info) == SmDispatch::Handled);
  assert(smDispatch(SmCommand::Arm) == SmDispatch::Handled);
  assert(smDispatch(SmCommand::Disarm) == SmDispatch::Handled);
  assert(smDispatch(SmCommand::SetPassword) == SmDispatch::Handled);

  // --- THE safety invariant: no input other than a clean `sm_wipe` can produce WipeRequest ---
  const char* nonWipe[] = {
      "sm_status", "sm_info", "sm_arm", "sm_disarm", "sm_set_password",
      "sm_wipex", "sm_wipe\t", "sm_reboot", "sm_stat", "sm_statusx", "sm_", "sm_ wipe",
  };
  for (const char* line : nonWipe) {
    assert(smDispatch(classifySmCommand(line)) != SmDispatch::WipeRequest);
  }
  // ...and the clean forms DO.
  assert(smDispatch(classifySmCommand("sm_wipe")) == SmDispatch::WipeRequest);
  assert(smDispatch(classifySmCommand("sm_wipe ")) == SmDispatch::WipeRequest);

  return 0;  // reaching here == every assert passed
}
