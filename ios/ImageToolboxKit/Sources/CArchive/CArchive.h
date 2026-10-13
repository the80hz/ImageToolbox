#ifndef IMAGETOOLBOX_CARCHIVE_H
#define IMAGETOOLBOX_CARCHIVE_H

// The part of libarchive's <archive.h> that ImageToolboxKit reads RAR archives with. The SDKs ship
// libarchive.tbd without its header, so the declarations are repeated here with the names and types
// of the original. The status codes are not declared; they are written out in RARReader.swift.

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

struct archive;
struct archive_entry;

typedef ssize_t la_ssize_t;
typedef int64_t la_int64_t;

struct archive *archive_read_new(void);
int archive_read_support_format_rar(struct archive *);
int archive_read_support_format_rar5(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_open_memory(struct archive *, const void *buff, size_t size);
int archive_read_next_header(struct archive *, struct archive_entry **);
la_ssize_t archive_read_data(struct archive *, void *buff, size_t size);
const char *archive_entry_pathname(struct archive_entry *);
la_int64_t archive_entry_size(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int archive_read_close(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);

#endif /* IMAGETOOLBOX_CARCHIVE_H */
