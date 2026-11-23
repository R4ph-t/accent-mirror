# Praat's autocorrelation pitch for scripts/pitch-real-clips.sh (spec 04, Open question 1).
# Saves the clip as 16 kHz mono (what pyin-1 is given) and, from that, one line per 10 ms frame: time in seconds,
# then F0 in Hz (0 when Praat calls the frame unvoiced).
# Settings match pyin-1's search range (60-500 Hz) and hop (10 ms); the rest are Praat's standard defaults.
form Pitch
    sentence wav
    sentence wav16k
    sentence out
endform
original = Read from file: wav$
mono = Convert to mono
sound = Resample: 16000, 50
Save as WAV file: wav16k$
pitch = To Pitch (ac): 0.01, 60, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 500
frames = Get number of frames
deleteFile: out$
for i to frames
    t = Get time from frame number: i
    f0 = Get value in frame: i, "Hertz"
    if f0 = undefined
        f0 = 0
    endif
    appendFileLine: out$, fixed$(t, 4), " ", fixed$(f0, 3)
endfor
