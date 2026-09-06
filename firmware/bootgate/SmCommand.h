// SmCommand.h — pure, dependency-free classification of a dashboard "sm_" serial command.
//
// This is the DECISION half of the Cyber-Controller dashboard protocol, split out from the Serial
// I/O in GateInput_serial.cpp so it can be unit-tested and statically compiled on a host with no
// Arduino/Serial/NVS dependencies. It exists to fix the W1 wipe-misfire (audit
// DEADMANS-AUDIT-2026-07-12 §GateInput_serial.cpp:313): the old caller overloaded a `bool` return
// so that BOTH a deliberate `sm_wipe` AND any unrecognized `sm_` line returned `false`, and then
// unconditionally routed `false` into the authenticated wipe prompt. A typo (`sm_reboot`), an
// unknown/future command, or a mangled keyword therefore dropped the operator into the wipe flow;
// entering the correct password there fired an irreversible wipe.
//
// SPEC §6.1: an unrecognized SM_ command is a deferred error reply — NEVER a password attempt, and
// NEVER the wipe path. The tri-state below makes that impossible to conflate: ONLY a clean `sm_wipe`
// maps to WipeRequest; everything else is Handled (in place) or Unknown (rejected + re-prompt).
#ifndef SUICIDE_SM_COMMAND_H
#define SUICIDE_SM_COMMAND_H

#include <stddef.h>

namespace suicide {
namespace dashboard {

// The recognized dashboard commands, plus the catch-all Unknown.
enum class SmCommand {
  Status,       // sm_status       -> emit status JSON (handled in place)
  Info,         // sm_info         -> emit info JSON (handled in place)
  Arm,          // sm_arm          -> "re-provision required" reply (handled in place)
  Disarm,       // sm_disarm       -> "re-provision required" reply (handled in place)
  SetPassword,  // sm_set_password -> "re-provision required" reply (handled in place)
  Wipe,         // sm_wipe         -> route to the AUTHENTICATED wipe flow
  Unknown,      // anything else sm_-prefixed -> reject + re-prompt, NEVER wipe, NEVER an attempt
};

// What the getPassword() caller must do with a classified command.
enum class SmDispatch {
  Handled,      // fully processed here -> re-prompt, not a password attempt
  WipeRequest,  // the deliberate sm_wipe -> hand off to the authenticated wipe flow
  Unknown,      // unrecognized sm_ line -> emit an error, re-prompt, never a wipe / never an attempt
};

// Case-insensitive ASCII prefix match (dashboard commands are lowercase ASCII). Mirrors the
// startsWithCmd() helper in GateInput_serial.cpp; kept here so this header stays self-contained.
inline bool smPrefix(const char* line, const char* cmd, size_t cmdLen) {
  for (size_t i = 0; i < cmdLen; ++i) {
    char c = line[i];
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    if (c != cmd[i]) return false;
  }
  return true;
}

// A recognized command must be the WHOLE token: the keyword followed by end-of-string or a space.
// A trailing tab or any extra byte (`sm_wipex`, `sm_wipe\t`) is therefore NOT a match and falls to
// Unknown -- the safe choice for a misfire fix: a mangled `sm_wipe` must never reach the wipe flow.
// (Preserves the exact '\0'/' ' terminator behaviour of the original processCommand checks.)
inline bool smExact(const char* line, const char* cmd, size_t cmdLen) {
  return smPrefix(line, cmd, cmdLen) && (line[cmdLen] == '\0' || line[cmdLen] == ' ');
}

// Classify a trimmed line. The caller guarantees it starts with "sm_"; a bare "sm_" or any
// unrecognized "sm_..." returns Unknown.
inline SmCommand classifySmCommand(const char* trimmed) {
  if (smExact(trimmed, "sm_status", 9))        return SmCommand::Status;
  if (smExact(trimmed, "sm_info", 7))          return SmCommand::Info;
  if (smExact(trimmed, "sm_arm", 6))           return SmCommand::Arm;
  if (smExact(trimmed, "sm_disarm", 9))        return SmCommand::Disarm;
  if (smExact(trimmed, "sm_set_password", 15)) return SmCommand::SetPassword;
  if (smExact(trimmed, "sm_wipe", 7))          return SmCommand::Wipe;
  return SmCommand::Unknown;
}

// Map a classified command to the caller's dispatch outcome. ONLY Wipe -> WipeRequest; this is the
// single choke point that guarantees no unrecognized command can ever reach the wipe path.
inline SmDispatch smDispatch(SmCommand cmd) {
  switch (cmd) {
    case SmCommand::Wipe:    return SmDispatch::WipeRequest;
    case SmCommand::Unknown: return SmDispatch::Unknown;
    default:                 return SmDispatch::Handled;  // Status/Info/Arm/Disarm/SetPassword
  }
}

}  // namespace dashboard
}  // namespace suicide

#endif  // SUICIDE_SM_COMMAND_H
