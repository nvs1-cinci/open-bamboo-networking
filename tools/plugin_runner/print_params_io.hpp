#ifndef OBN_PLUGIN_RUNNER_PRINT_PARAMS_IO_HPP
#define OBN_PLUGIN_RUNNER_PRINT_PARAMS_IO_HPP

#include <string>
#include <vector>

#include "obn/bambu_networking.hpp"

namespace obn::plugin_runner {

// Loads a JSON file (the `--params-json` schema this binary accepts —
// see `kKnownKeys` in print_params_io.cpp for the full list of fields)
// and overlays present keys onto `out`. Missing keys keep whatever `out`
// already had. Unknown / type-mismatched keys are appended to `warnings`
// and ignored. Throws std::runtime_error if the file cannot be opened or
// parsed.
void load_print_params_from_json(const std::string&    json_path,
                                 BBL::PrintParams&     out,
                                 std::vector<std::string>& warnings);

} // namespace obn::plugin_runner

#endif // OBN_PLUGIN_RUNNER_PRINT_PARAMS_IO_HPP
