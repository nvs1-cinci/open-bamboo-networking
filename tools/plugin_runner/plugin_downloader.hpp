#ifndef OBN_PLUGIN_RUNNER_PLUGIN_DOWNLOADER_HPP
#define OBN_PLUGIN_RUNNER_PLUGIN_DOWNLOADER_HPP

#include <optional>
#include <string>

namespace obn::plugin_runner {

struct DownloadResult {
    bool        ok = false;
    std::string so_path;       // absolute path to libbambu_networking.so when ok
    std::string version;       // resolved plugin version, e.g. "01.10.04.00"
    std::string error_message; // populated when !ok
    int         http_status = 0;
};

// Implementation of the same workflow Studio's PresetUpdater uses to
// auto-install / refresh the network plugin:
//   1. GET https://api.bambulab.com/v1/iot-service/api/slicer/resource
//          ?slicer/plugins/cloud=<MM.mm.pp>.00
//   2. Parse the resources[] array, pick the entry with the type
//      "slicer/plugins/cloud", read its `url` and `version`.
//   3. Download the zip from `url` into a tmp file.
//   4. Extract `libbambu_networking.so` from the zip into
//      `<cache_dir>/<version>/`.
//   5. Return its absolute path.
//
// `cache_dir` is created if missing. If the cache already has a .so for
// the resolved version, the network step is skipped (use force=true to
// re-download).
//
// abi_prefix must be exactly "MM.mm.pp" with three dotted decimal
// components — the wrapper script gets it from the user's --abi flag.
DownloadResult fetch_plugin(const std::string& abi_prefix,
                            const std::string& cache_dir,
                            bool               force = false);

} // namespace obn::plugin_runner

#endif // OBN_PLUGIN_RUNNER_PLUGIN_DOWNLOADER_HPP
