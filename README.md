# GenomicsDB: high-performance germline calling

This is a fork of [GenomicsDB](https://github.com/GenomicsDB/GenomicsDB). Its default branch, `high_performance_germline_calling`, is GenomicsDB 1.5.5 (upstream `master`) plus changes that speed up GATK joint calling (GenomicsDBImport, GnarlyGenotyper and GenotypeGVCFs), a few bug fixes, and a build for current toolchains, including Linux aarch64, whose native libraries run on any Linux with glibc 2.28 or later and on macOS 14 or later. It is used by the branch of the same name in [tfenne/gatk](https://github.com/tfenne/gatk).

Each change is on its own branch, cut from upstream `master`, so that it can be offered upstream as a pull request; this branch carries them all until they are merged. TileDB changes are in [tfenne/TileDB](https://github.com/tfenne/TileDB), which this branch builds instead of upstream's TileDB.

For GenomicsDB itself (documentation, the Java and C++ APIs, support), see the [upstream README](https://github.com/GenomicsDB/GenomicsDB/blob/master/README.md).

> [!TIP]
> **For 1,000 samples over 16 Mb of chr20, this branch cuts GenomicsDBImport from 788.7 s to 425.0 s (−46%) and GnarlyGenotyper from 2,936.4 s to 828.2 s (−72%), with byte-identical output.** Later changes take GnarlyGenotyper with GATK's settings from 515.3 s to 428.2 s (−17%) and then a further 5.5%, or −23% and then −4.3% with allele-specific annotations; GenotypeGVCFs 15% lower; and GenomicsDBImport a further 13%, or 28% with allele-specific annotations. Most of the genotyping gain needs GATK to ask for it; tfenne/gatk does.

## Results

1,000 samples × 16 Mb of chr20 (see [How we benchmarked](#how-we-benchmarked)), each row adding one change to the row above:

| GenomicsDBImport | Wall time |
|---|---|
| Stock GenomicsDB 1.5.5, lz4 tiles, shared-posixfs, only the fields the gVCFs use declared | 788.7 s |
| + fields resolved once per file, readers cast once per partition (`perf/vcf-import`) | **425.0 s** |

| GnarlyGenotyper | Wall time |
|---|---|
| Stock GenomicsDB 1.5.5, gzip workspace | 2,936.4 s |
| + reference-only intervals skipped (`perf/combined-gvcf-query`, with tfenne/gatk) | 1,213.6 s |
| + attribute files held open across tile reads (tfenne/TileDB) | 910.7 s |
| + compressed tiles read with `pread` (tfenne/TileDB) | 889.3 s |
| + per-cell copies and TileDB's C API checks (`perf/combined-gvcf-query`, tfenne/TileDB) | **828.2 s** |

Each row was measured in a different benchmark pass, and times drift by up to ±10% between passes, so the small steps are more reliable as the same-pass pairs in [What's changed](#whats-changed-on-this-branch). GATK-side settings (lz4 tiles, the BCF codec, a header of only the fields in use) bring Gnarly to 524.4 s and import plus Gnarly from 4,987 s to 949 s; those are described in tfenne/gatk.

With those GATK settings, the later changes, measured in two same-pass sets:

| GnarlyGenotyper | Without AS annotations | With AS annotations |
|---|---|---|
| The changes above | 515.3 s | 683.7 s |
| + INFO fields combined without work on calls that lack them (`perf/info-field-combine`) | 492.8 s | 603.5 s |
| + records whose only ALTs are `*` and `<NON_REF>` skipped (`perf/combined-gvcf-query`, with tfenne/gatk) | 476.3 s | – |
| + per-cell and per-record overheads (`perf/query-overheads`, tfenne/TileDB) | **428.2 s** | **527.8 s** ² |

² The allele-specific set measured the last row with the skip included, but not the skip on its own.

The same skip takes GenotypeGVCFs from 1,889.5 s to 1,607.0 s (−15.0%). Link-time optimisation (`build/modern-toolchains`), measured separately, takes Gnarly on the allele-specific set from 685.8 s to 675.5 s (−1.5%) and imports 1–2% lower.

Measured later, each against a build with everything above:

| Change | Without AS annotations | With AS annotations |
|---|---|---|
| GenomicsDBImport: only the fields each record has fetched, allele-specific annotations parsed without allocating, per-field settings resolved once per file (`perf/vcf-import`) | 448.6 → 390.1 s (−13.1%) | 490.6 → 355.9 s (−27.5%) |
| GnarlyGenotyper: FORMAT fields gathered without work on calls that lack them, cheaper allele merging (`perf/info-field-combine`, `perf/query-overheads`) | 414.0 → 391.2 s (−5.5%) | 502.4 → 480.9 s (−4.3%) |

On Linux x86-64 (AWS r8a.4xlarge, AMD Zen 5), with 100 of the 3,202 1000 Genomes samples called by HaplotypeCaller in DRAGEN mode with allele-specific annotations and reblocked, imported from BCFs over the same region: building htslib with libdeflate (`build/modern-toolchains`) takes GenomicsDBImport from 35.7 s to 32.5 s (−9.0%), with byte-identical workspaces. The host's stock zlib 1.2.11 had spent 11.6% of the import's CPU time decompressing BGZF blocks, against 4.3% for macOS's zlib on the same data; the gain on macOS wasn't measured.

## How we benchmarked

- **Data:** the NYGC 1000 Genomes high-coverage per-sample gVCFs (GRCh38, ~30x), reblocked with WARP's `ReblockGVCF` arguments, over chr20 1–16 Mb (WARP's calling regions). 1,000 samples, drawn in a fixed shuffled order, so smaller cohorts are subsets of larger ones.
- **Allele-specific annotations:** the NYGC gVCFs lack them, so the same samples were also given `AS_RAW_MQ`, `AS_SB_TABLE` and the `AS_RAW_*RankSum` fields in GATK's formats, derived from each record's own values. GenomicsDB combines them by field name, so this exercises the same code as real allele-specific annotations.
- **Tools:** GATK from tfenne/gatk, importing each shard as a single batch with GenomicsDB's native reader (`--bypass-feature-reader`), then GnarlyGenotyper with WARP's arguments.
- **Hardware:** one Apple M-series Mac, single-threaded, inputs in the page cache.
- **Checks:** every change gives byte-identical genotyping output, and import changes give byte-identical workspace files, compared file by file. Each change was also compared with the build before it on GenomicsDB's own tests and a set of synthetic import and query cases.

## What's changed on this branch?

Effects are measured as pairs in the same benchmark pass, at 100 / 1,000 samples. No change alters the on-disk format: workspaces are interchangeable with upstream GenomicsDB 1.5.5.

| Branch | PR | Change | Changes output? | Effect |
|---|---|---|---|---|
| [`fix/callset-json-int64`](https://github.com/tfenne/GenomicsDB/tree/fix/callset-json-int64) | – | A JSON callset mapping whose `row_idx` and `idx_in_file` are strings, as protobuf's JSON writes them (GATK's `callset.json` does), was read as the strings' raw bytes, so FORMAT values came from the wrong sample or from memory past the record. Such values are now parsed, anything else is an error, and a sample index beyond the VCF's samples is an error. | Yes, for such mappings: it was wrong | bug fix |
| [`fix/combined-gvcf-gt-leak`](https://github.com/tfenne/GenomicsDB/tree/fix/combined-gvcf-gt-leak) | – | The combined gVCF operator leaked the genotype array of every record with a sample whose GQ or PL[0] is 0. | No | bug fix |
| [`fix/import-progress-flag-type`](https://github.com/tfenne/GenomicsDB/tree/fix/import-progress-flag-type) | – | The import progress flag was declared `int` where it is used and defined `bool`, so the importer read four bytes of a one-byte object. | No | bug fix |
| [`fix/jni-native-exceptions`](https://github.com/tfenne/GenomicsDB/tree/fix/jni-native-exceptions) | – | A C++ exception escaping a JNI function aborted the JVM, e.g. from `GenomicsDBUtils.readEntireFile` on a missing file; every JNI entry point now turns one into a `GenomicsDBException`. | No | bug fix |
| [`build/modern-toolchains`](https://github.com/tfenne/GenomicsDB/tree/build/modern-toolchains) | – | Builds with CMake 4, GCC 15, clang 21 and Apple clang 21, and on Linux aarch64 (with `-fsigned-char`, since the missing value for char fields depends on char's signedness). Dependencies the build makes go in a git-ignored `deps/`, per toolchain, instead of `$HOME`. Release builds with clang link GenomicsDB and TileDB with ThinLTO, so GenomicsDB inlines TileDB's per-cell calls; GCC builds don't, since GCC 15's LTO stops with an internal compiler error on x86-64. The jar holds one native library per platform, in `linux-x86_64/`, `linux-aarch64/` and so on. htslib is built with libdeflate, linked in statically, so BGZF blocks are read and written without the system zlib, which on Linux hosts with a stock zlib took 10–12% of an import's CPU time. With `BUILD_DISTRIBUTABLE_LIBRARY` on Linux, OpenSSL 3.5, libcurl and libuuid are built as static libraries and linked in with libstdc++, so the library depends only on glibc 2.28 or later and zlib, and it finds the distribution's CA certificates where `/etc/ssl` has none, as on RHEL 8; on macOS, OpenSSL is built statically for the minimum macOS version in `MACOSX_DEPLOYMENT_TARGET`, so the library needs only macOS's own libraries. | No | build; LTO Gnarly −1.5% at 1,000, import −1–2% at 100; libdeflate import −9.0% at 100 on x86-64 Linux |
| [`perf/combined-gvcf-query`](https://github.com/tfenne/GenomicsDB/tree/perf/combined-gvcf-query) | – | An opt-in export option, `skip_reference_only_intervals`, skips intervals where every active call is a reference block, and a second, `skip_spanning_deletion_only_intervals`, drops records whose merged ALTs are only `*` and `<NON_REF>` (22% of records at 1,000 samples), which GATK discards unused; tfenne/gatk sets both for Gnarly and for GenotypeGVCFs unless non-variant sites are requested. Also per-sample flags instead of per-record sets for GQ==0/PL[0]==0, and field copies without a zero-fill. | Only when enabled: records GATK discards are not produced | Gnarly −39% / −59%, GenotypeGVCFs −44% at 100 (reference-only skip); spanning-deletion skip Gnarly −3.4%, GenotypeGVCFs −15.0% at 1,000; copies with TileDB's inline checks −8.5% / −3.6% |
| [`perf/info-field-combine`](https://github.com/tfenne/GenomicsDB/tree/perf/info-field-combine) | – | INFO fields are combined without copying, casting or remapping them for calls that lack them, which for allele-specific fields is most calls (reference blocks); casts whose type is fixed by construction are static, and the allele-specific remap copies less. Likewise, FORMAT fields such as AD and PL are not copied for calls that lack them, and are gathered for htslib in one pass without virtual calls; reference blocks skip the REF when alleles are merged and keep their GT without remapping. | No | Gnarly −4.4% at 1,000 (−11.7% with allele-specific annotations) for INFO; then −5.5% (−4.3%) for FORMAT and allele merging, with part of `perf/query-overheads` |
| [`perf/query-overheads`](https://github.com/tfenne/GenomicsDB/tree/perf/query-overheads) | – | The allele look-up tables are reset only where written instead of in full per record (a 1–2 MB memset at 1,000 samples), with fixed-width stores rather than a memset per row; a missing field is recognised before it is copied; END copies of cells are skipped before all their attributes are fetched. | No | Gnarly −9.9% at 1,000, with the TileDB iterator change |
| [`perf/vcf-import`](https://github.com/tfenne/GenomicsDB/tree/perf/vcf-import) | – | Each INFO/FORMAT field is resolved once per input file instead of by name per record, and only the fields a record has are fetched from htslib; the readers are cast once per partition instead of `dynamic_cast` per field per record; allele-specific annotations, strings in the gVCF, are parsed without allocating per value; a `vcf_read_buffer_size` import option (default 64 KiB) for VCF files read directly. | No | import −33% / −26% ¹ (fields), then −34% / −27% ¹ (casts); then −13.1% at 1,000 (−27.5% with allele-specific annotations) for fetching and parsing |
| [`fork/tiledb`](https://github.com/tfenne/GenomicsDB/tree/fork/tiledb) | fork only | Builds TileDB from [tfenne/TileDB](https://github.com/tfenne/TileDB): attribute files held open across tile reads, compressed tiles read with `pread`, inline C API checks, zstd compiled in (upstream loads `libzstd` at run time and aborts the JVM without it) with its decompression context freed correctly (upstream crashed in 6 of 100 runs of a small zstd query, at thread exit), a build for current toolchains, an array iterator that no longer copies its attribute list on every cell, and cloud SDKs built against TileDB's OpenSSL and libcurl, so that both can be static; reading a whole file no longer frees the wrong pointer when the read fails. | No | Gnarly −26% / −25% (files held open), −6.5% / −11% (`pread`) |
| [`fork/meta`](https://github.com/tfenne/GenomicsDB/tree/fork/meta) | fork only | This README, the fork's CI, the licence notices of the software compiled into the native libraries (`THIRD-PARTY-NOTICES.txt`, which the jar carries) and the jar's Maven coordinates, `com.tfenne:genomicsdb`. | – | – |

¹ With the gVCF header as written / with only the fields in use declared.

## Running it

Build as upstream GenomicsDB builds, from a recursive clone of this branch:

```bash
git clone --recursive --branch high_performance_germline_calling https://github.com/tfenne/GenomicsDB.git
cmake -S GenomicsDB -B GenomicsDB/build -DCMAKE_BUILD_TYPE=Release -DBUILD_JAVA=1 -DGENOMICSDB_RELEASE_VERSION=1.6.0-local
cmake --build GenomicsDB/build --target genomicsdb-1.6.0-local-examples -j 8
```

- **Toolchains:** CMake 3.22 or later (4.x works), with GCC 15, clang 21 or Apple clang 21; CI builds on AlmaLinux 8 (glibc 2.28) with GCC on x86-64 and clang on aarch64, and on macOS 14 with Apple clang. Needs zlib, OpenSSL, libcurl and libuuid, plus a JDK 17 and Maven for the jar.
- **Distributable library:** `-DBUILD_DISTRIBUTABLE_LIBRARY=1` builds OpenSSL 3.5 from source into `deps/` and links it in statically. On Linux, libcurl and libuuid are built and linked in too, with libstdc++, so the library runs on any Linux with glibc 2.28 or later and zlib; OpenSSL's build needs Perl's `IPC::Cmd` and `Time::Piece`. OpenSSL looks for CA certificates under `/etc/ssl`; where that has none, as on RHEL 8, the library points it at the distribution's CA bundle unless `SSL_CERT_FILE` or `SSL_CERT_DIR` is set. On macOS, set `MACOSX_DEPLOYMENT_TARGET`, e.g. to 14.0, for both the configure and the build: every dependency built from source targets that version, and the library needs only macOS's own libraries.
- **First build:** protobuf, libdeflate and TileDB's cloud SDKs are built into `deps/`, which takes 10–20 minutes; later builds with the same compiler reuse them. Set `GENOMICSDB_DEPS_DIR` to keep them elsewhere.
- **Instruction set:** `-DBUILD_FOR_ARCH=<-march value>`, e.g. `x86-64-v3`, compiles GenomicsDB, TileDB and htslib for that instruction set. By default the compiler's own default is used, which for GCC on x86-64 is the original 64-bit instruction set.
- **Link-time optimisation:** on for Release builds with clang (not GCC). `-DENABLE_LTO=OFF` turns it off, e.g. for profiling, where inlining folds TileDB's frames into GenomicsDB's, or to link the installed static library without LTO.
- **With GATK:** install the jar locally (`mvn install:install-file -Dfile=GenomicsDB/build/target/genomicsdb-1.6.0-local.jar -DpomFile=GenomicsDB/build/pom.xml`), which installs it as `com.tfenne:genomicsdb:1.6.0-local`, and build tfenne/gatk against it (`./gradlew localJar -Dgenomicsdb.version=1.6.0-local`).
- **Jars from CI** carry distributable native libraries for Linux x86-64 and aarch64 and macOS arm64.

## How the branch is maintained

The branch is upstream `master` with each branch above merged in, plus fork-only branches (the TileDB switch, this README and CI). It only moves forward once released. Upstream is merged in periodically, and a branch that changes in review is merged in again. A pull request that is merged upstream arrives through the next upstream merge.
