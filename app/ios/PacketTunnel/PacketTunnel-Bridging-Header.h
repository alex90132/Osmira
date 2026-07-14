#ifndef PacketTunnel_Bridging_Header_h
#define PacketTunnel_Bridging_Header_h

#include <stdint.h>

// C symbols exported by the AmneziaWG-Go backend (amneziawg-apple /
// amneziawg-go-apple). The AWG2 fields (Jc/Jmin/Jmax/S1..S4/H1..H4/I1..I5)
// travel inside the `settings` UAPI string, exactly as on Android.
//
// NOTE: verify the symbol names against the amneziawg-apple version you link.
// Upstream wireguard-apple exports these as wg*; if your fork exports awg*,
// rename accordingly here.
extern int32_t wgTurnOn(const char *settings, int32_t tun_fd);
extern void wgTurnOff(int32_t handle);
extern int64_t wgSetConfig(int32_t handle, const char *settings);
extern char *wgGetConfig(int32_t handle);
extern int32_t wgGetSocketV4(int32_t handle);
extern int32_t wgGetSocketV6(int32_t handle);
extern const char *wgVersion(void);

#endif /* PacketTunnel_Bridging_Header_h */
