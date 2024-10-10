//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const portmidi = @cImport({
    // @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("portmidi.h");
    @cInclude("porttime.h");
});

const GRIDCOLOR = 117;
const ACCENTCOLOR = 116;
const WHITE = 3;
const GREEN = 32;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;
    _ = portmidi.Pm_Initialize();
    defer _ = portmidi.Pm_Terminate();

    const device_count = @as(usize, @intCast(portmidi.Pm_CountDevices()));
    for (0..device_count) |i| {
        const device = portmidi.Pm_GetDeviceInfo(@intCast(i));
        std.debug.print("Name: {s}, Input?: {}, Output?: {}\n", .{ device.*.name, device.*.input, device.*.output });
    }
    _ = portmidi.Pt_Start(10, &ptCallback, null);
    defer _ = portmidi.Pt_Stop();
    var launchpadInput: ?*portmidi.PmStream = null;
    _ = portmidi.Pm_OpenInput(&launchpadInput, 7, null, 8, null, null);
    defer _ = portmidi.Pm_Close(launchpadInput);

    var launchpadOut: ?*portmidi.PmStream = null;
    _ = portmidi.Pm_OpenOutput(&launchpadOut, 6, null, 8, null, null, 16);
    defer _ = portmidi.Pm_Close(launchpadOut);

    var sequenceOut: ?*portmidi.PmStream = null;
    const sequenceId = portmidi.Pm_CreateVirtualOutput("Launchpad Sequencer Output", "ALSA", null);
    _ = portmidi.Pm_OpenOutput(&sequenceOut, sequenceId, null, 8, null, null, 16);
    defer _ = portmidi.Pm_Close(sequenceOut);

    var sequence: [8][8]bool = undefined;
    @memset(&sequence, [8]bool{ false, false, false, false, false, false, false, false });

    const notes = [8]u8{ 60, 62, 63, 65, 67, 68, 70, 72 };

    var playhead: u3 = 0;

    var boom = false;

    while (true) {
        var input_buffer: [8]portmidi.PmEvent = undefined;
        _ = portmidi.Pm_Read(launchpadInput, &input_buffer, 8);
        for (input_buffer) |value| {
            if (portmidi.Pm_MessageStatus(value.message) & 0xF0 == 0x90) {
                // const message = portmidi.Pm_Message(portmidi.Pm_MessageStatus(value.message), portmidi.Pm_MessageData1(value.message), portmidi.Pm_MessageData2(value.message));
                // var note_data = midiData(value.message);
                // note_data.note_val += 10;
                var notedata = get_message_note(value.message);
                std.debug.print("num: {}, vel: {}, channel: {}\n", .{ notedata.num, notedata.vel, notedata.chan });
                const b_x = notedata.num % 10 - 1;
                const b_y = notedata.num / 10 - 1;
                if (b_x != 9 and notedata.vel == 127) {
                    sequence[b_y][b_x] = !sequence[b_y][b_x];
                    if (sequence[b_y][b_x]) {
                        notedata.vel = WHITE;
                    } else {
                        notedata.vel = 0;
                    }
                    _ = portmidi.Pm_WriteShort(launchpadOut, value.timestamp, get_note_message(notedata));
                }
                // _ = portmidi.Pm_WriteShort(sequenceOut, value.timestamp, get_note_message(sequenceNoteOut));
            }
        }
        if (@rem(portmidi.Pt_Time(), 250) == 0) {
            if (boom) {
                try sequencer_row(launchpadOut, playhead, sequence);
                for (sequence, 0..) |rows, i| {
                    const is_playing = rows[playhead];
                    const was_playing = rows[@subWithOverflow(playhead, 1)[0]];
                    if (was_playing) {
                        const note = NoteData{
                            .num = notes[i],
                            .chan = 0,
                            .vel = 0,
                        };
                        _ = portmidi.Pm_WriteShort(sequenceOut, portmidi.Pt_Time(), get_note_message(note));
                    }

                    if (is_playing) {
                        const note = NoteData{
                            .num = notes[i],
                            .chan = 0,
                            .vel = 127,
                        };
                        _ = portmidi.Pm_WriteShort(sequenceOut, portmidi.Pt_Time() + 1, get_note_message(note));
                    }
                }
                playhead = @addWithOverflow(playhead, 1)[0];
            }
            boom = false;
        } else {
            boom = true;
        }
    }

    try bw.flush(); // Don't forget to flush!
}

fn ptCallback(_: portmidi.PtTimestamp, _: ?*anyopaque) callconv(.C) void {}

// const MIDINoteOn = struct {
//     note_val: u8,
//     velocity: u8 = 127,
// };

// fn midiData(data: u32) MIDINoteOn {
//     const val = @as(u8, (data >> 8)) & 0xFF;
//     const vel = @as(u8, (data >> 16)) & 0xFF;
//     return MIDINoteOn{ .note_val = val, .velocity = vel };
// }

// fn toMessage(porp: MIDINoteOn, channel: u4) u32 {
//     const status: u32 = 0x90 | @as(u32, channel);
//     const data1: u32 = porp.note_val >> 8;
//     const data2: u32 = porp.note_val >> 16;
//     return status | data1 | data2;
// }

fn get_note_message(data: NoteData) u32 {
    const status: u32 = 0x90 | @as(u32, data.chan);
    const data1: u32 = @as(u32, data.num) << 8;
    const data2: u32 = @as(u32, data.vel) << 16;
    return status | data1 | data2;
}

const NoteData = struct {
    num: u8,
    vel: u8,
    chan: u4,
};

fn get_message_note(data: u32) NoteData {
    const out = NoteData{
        .num = @as(u8, @intCast((data >> 8) & 0xFF)),
        .vel = @as(u8, @intCast((data >> 16) & 0xFF)),
        .chan = @as(u4, @intCast(data & 0x0F)),
    };
    return out;
}

inline fn is_white_key(num: u8) bool {
    const wrapped = num % 12;
    return wrapped == 0 or wrapped == 2 or wrapped == 4 or wrapped == 5 or wrapped == 7 or wrapped == 9 or wrapped == 11;
}

fn set_row(output: ?*portmidi.PmStream, column: u4, color: u8) !void {
    var message = [10]u8{ 0xf0, 0x00, 0x20, 0x29, 0x02, 0x18, 0x0c, @as(u8, column), color, 0xF7 };
    _ = portmidi.Pm_WriteSysEx(output.?, portmidi.Pt_Time(), &message);
}

fn sequencer_row(output: ?*portmidi.PmStream, column: u3, sequence: [8][8]bool) !void {
    try set_row(output, column, ACCENTCOLOR);
    try set_row(output, @subWithOverflow(column, 1)[0], 0);

    for (sequence, 0..) |rows, i| {
        for (rows, 0..) |cell, j| {
            if (cell) {
                var notedata = NoteData{ .num = @as(u8, @intCast(j + 11 + i * 10)), .vel = 127, .chan = 0 };
                if (j == column) {
                    notedata.vel = GREEN;
                } else {
                    notedata.vel = WHITE;
                }
                _ = portmidi.Pm_WriteShort(output, portmidi.Pt_Time(), get_note_message(notedata));
            }
        }
    }
}
