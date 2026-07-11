// tomlplusplus/mayhem/harnesses/toml_fuzzer.cpp
//
// Vendored copy of marzer/tomlplusplus' own OSS-Fuzz harness (fuzzing/toml_fuzzer.cpp), kept here
// so the mayhem build is self-contained and stable across upstream syncs. The fuzzed surface is the
// TOML PARSER: a random-length prefix of the input is parsed as TOML text via toml::parse(); on a
// successful parse the resulting toml::table is then fed through one of the JSON / YAML / TOML
// formatters (selected by a trailing enum byte) to also exercise the serializers. toml::parse_error
// is the library's well-defined "this isn't valid TOML" signal and is swallowed; any sanitizer trap
// (ASan/UBSan) or non-parse_error crash is a real finding.
//
// FuzzedDataProvider.h is shipped with clang's fuzzer runtime (the org base image provides it).

#include <cstdint>
#include <fuzzer/FuzzedDataProvider.h>

#include <toml++/toml.hpp>

enum class SerializationTest
{
    NONE = 0,
    JSON,
    YAML,
    TOML,
    kMaxValue = TOML
};

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, const std::size_t size)
{
    FuzzedDataProvider fdp{ data, size };
    try
    {
        const toml::table tbl = toml::parse(fdp.ConsumeRandomLengthString());

        switch (fdp.ConsumeEnum<SerializationTest>())
        {
            case SerializationTest::JSON: static_cast<void>(toml::json_formatter{ tbl }); break;
            case SerializationTest::YAML: static_cast<void>(toml::yaml_formatter{ tbl }); break;
            case SerializationTest::TOML: static_cast<void>(toml::toml_formatter{ tbl });
            default: break;
        }
    }
    catch (const toml::parse_error&)
    {
        return -1;
    }
    return 0;
}
