const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Terminal = @import("../Terminal.zig");
const command = @import("graphics_command.zig");
const image = @import("graphics_image.zig");
const Command = command.Command;
const Response = command.Response;
const Image = image.Image;

/// Execute a Kitty graphics command against the given terminal. This
/// will never fail, but the response may indicate an error and the
/// terminal state may not be updated to reflect the command. This will
/// never put the terminal in an unrecoverable state, however.
///
/// The allocator must be the same allocator that was used to build
/// the command.
pub fn execute(
    alloc: Allocator,
    terminal: *Terminal,
    buf: []u8,
    cmd: *Command,
) ?Response {
    _ = terminal;
    _ = buf;

    const resp_: ?Response = switch (cmd.control) {
        .query => query(alloc, cmd),
        .transmit => transmit(alloc, cmd),
        else => .{ .message = "ERROR: unimplemented action" },
    };

    // Handle the quiet settings
    if (resp_) |resp| {
        return switch (cmd.quiet) {
            .no => resp,
            .ok => if (resp.ok()) null else resp,
            .failures => null,
        };
    }

    return null;
}

/// Execute a "query" command.
///
/// This command is used to attempt to load an image and respond with
/// success/error but does not persist any of the command to the terminal
/// state.
fn query(alloc: Allocator, cmd: *Command) Response {
    const t = cmd.control.query;

    // Query requires image ID. We can't actually send a response without
    // an image ID either but we return an error and this will be logged
    // downstream.
    if (t.image_id == 0) {
        return .{ .message = "EINVAL: image ID required" };
    }

    // Build a partial response to start
    var result: Response = .{
        .id = t.image_id,
        .image_number = t.image_number,
        .placement_id = t.placement_id,
    };

    // Attempt to load the image. If we cannot, then set an appropriate error.
    var img = Image.load(alloc, cmd) catch |err| {
        encodeError(&result, err);
        return result;
    };
    img.deinit(alloc);

    return result;
}

/// Transmit image data.
fn transmit(alloc: Allocator, cmd: *Command) Response {
    const t = cmd.control.transmit;
    var result: Response = .{
        .id = t.image_id,
        .image_number = t.image_number,
        .placement_id = t.placement_id,
    };

    // Load our image. This will also validate all the metadata.
    var img = Image.load(alloc, cmd) catch |err| {
        encodeError(&result, err);
        return result;
    };
    errdefer img.deinit(alloc);

    // Store our image
    // TODO
    img.deinit(alloc);

    return result;
}

const EncodeableError = Image.Error;

/// Encode an error code into a message for a response.
fn encodeError(r: *Response, err: EncodeableError) void {
    switch (err) {
        error.InvalidData => r.message = "EINVAL: invalid data",
        error.UnsupportedFormat => r.message = "EINVAL: unsupported format",
        error.DimensionsRequired => r.message = "EINVAL: dimensions required",
        error.DimensionsTooLarge => r.message = "EINVAL: dimensions too large",
    }
}
