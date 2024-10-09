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

    try show_grid(launchpadOut);

    while (true) {
        var input_buffer: [8]portmidi.PmEvent = undefined;
        _ = portmidi.Pm_Read(launchpadInput, &input_buffer, 8);
        for (input_buffer) |value| {
            if (portmidi.Pm_MessageStatus(value.message) & 0xF0 == 0x90) {
                // const message = portmidi.Pm_Message(portmidi.Pm_MessageStatus(value.message), portmidi.Pm_MessageData1(value.message), portmidi.Pm_MessageData2(value.message));
                // var note_data = midiData(value.message);
                // note_data.note_val += 10;
                var notedata = get_message_note(value.message);
                const sequenceNoteOut = map_launchpad_to_note(notedata, notedata.vel);

                std.debug.print("num: {}, vel: {}, channel: {}\n", .{ notedata.num, notedata.vel, notedata.chan });
                if (notedata.vel != 0) {
                    notedata.vel = WHITE;
                } else {
                    if (is_white_key(sequenceNoteOut.num)) {
                        notedata.vel = ACCENTCOLOR;
                    } else {
                        notedata.vel = GRIDCOLOR;
                    }
                }
                _ = portmidi.Pm_WriteShort(launchpadOut, value.timestamp, get_note_message(notedata));

                _ = portmidi.Pm_WriteShort(sequenceOut, value.timestamp, get_note_message(sequenceNoteOut));
            }
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

fn show_grid(output: ?*portmidi.PmStream) !void {
    const time = portmidi.Pt_Time();
    for (1..9) |i| {
        for (1..9) |j| {
            const iu8 = @as(u8, @intCast(i));
            const ju8 = @as(u8, @intCast(j));
            var gridcolor: u8 = GRIDCOLOR;
            if (is_white_key((ju8 - 1) * 5 + (iu8 - 1))) {
                gridcolor = ACCENTCOLOR;
            }

            const noteData = NoteData{ .num = (ju8 * 10) + iu8, .vel = gridcolor, .chan = 0 };

            _ = portmidi.Pm_WriteShort(output.?, time, get_note_message(noteData));
        }
    }
}

fn map_launchpad_to_note(notedata: NoteData, velocity: u8) NoteData {
    const y = notedata.num / 10;
    const x = notedata.num % 10;
    var outNote = (x - 1) + (y - 1) * 5;
    outNote += 60;
    return NoteData{ .num = outNote, .vel = velocity, .chan = 0 };
}

inline fn is_white_key(num: u8) bool {
    const wrapped = num % 12;
    return wrapped == 0 or wrapped == 2 or wrapped == 4 or wrapped == 5 or wrapped == 7 or wrapped == 9 or wrapped == 11;
}
