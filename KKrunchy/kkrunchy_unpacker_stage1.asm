format binary
use32
include 'INCLUDE/win32a.inc'

image_base = 007C0000h

input_data_pointer = 007C00D4h
output_data_pointer = 007E3DA9h
import_offset_in_output = 02FCh

org 7D7A0Ch

entry_point:
	MOV EBP, data_for_decompressor		; TEMPORARY AREA FOR DECOMPRESSOR
	MOV dword [EBP], input_data_pointer	; INPUT STREAM
	CLD
	DEC dword [EBP + 8]			; RANGE (IN BEGINNING WE ARE WORKING WITH
						; ARITHMETIC ENCODER FROM 0 ALL THE WAY
						; THROUGH FFFFFFFFh)
	XOR EDX, EDX

	LEA EDI, [EBP + models - data_for_decompressor]		; DATA FOR MODELS WILL BE STORED HERE
	MOV ESI, models_info			; INFO ABOUT MODELS
	MOV DL, 7				; NUMBER OF MODELS (7 + 1 = 8)
	XOR ECX, ECX

next_model:
	XOR EAX, EAX
	STOSD					; STORE 0 TO SEPARATE MODELS FROM EACH OTHER

	LODSB					; GET THRESHOLD
	SHL EAX, 3				; * 8
	STOSD					; SAVE THRESHOLD

	MOV [EBP + 4 * EDX + model_0_pointer - data_for_decompressor], EDI		; POINTER TO MODEL DATA

	XOR EAX, EAX
	LODSB					; GET NUMBER OF SYMBOLS - 1
	INC EAX
	STOSD					; SAVE NUMBER OF SYMBOLS

	XCHG EAX, ECX				; ECX = NUMBER OF SYMBOLS FOR CURRENT MODEL

	INC EAX
	REP STOSD				; SAVE SYMBOL FREQUENCIES (FOR NOW EACH SYMBOL HAS FREQUENCY OF 1)

	DEC EDX
	JNS next_model				; TO NEXT MODEL

						; ECX = 0 INITIALLY

	MOV EDI, output_data_pointer		; OUTPUT STREAM ADDRESS
	PUSH EDI				; PUSH FOR JMP'ING TO THAT ADDRESS LATER BY 'RET'

; ALGORITHM
; 1. GET BYTE FROM MODEL #0 AND OUTPUT IT
; 2. IF LAST TIME WE OUTPUT JUST ORDINARY BYTE FROM MODEL #0 - GET BIT FROM MODEL #3 ELSE GET BIT FROM MODEL #4
; 3. IF BIT FROM STEP 2 IS 0 - GO TO STEP 1 ELSE CONTINUE
; 4. IF LAST TIME WE COPIED BYTES FROM PREVIOUS BYTES TO OUTPUT - GO TO STEP 10
; 5. READ BIT FROM MODEL #7
; 6. IF BIT FROM STEP 5 = 0: GO TO STEP 10 ELSE CONTINUE
; 7. READ STREAM OF BITS FROM MODEL #2
; 8. COPY BYTES THAT WERE IN OUTPUT BEFORE BY THE VARIABLE "OLD_DISPLACEMENT" BYTES, LENGTH IS EQUAL TO NUMBER FROM STEP 7
; 9. GO TO STEP 2
; 10. READ STREAM OF BITS FROM MODEL #1
; 11. IF RESULT IN STEP 10 == 1, UNPACKING ENDS
; 12. IF RESULT IN STEP 10 == 2, SET VARIABLE "MODEL" TO #6 ELSE SET VARIABLE "MODEL" TO #5
; 13. READ STREAM OF BITS FROM MODEL SPECIFIED IN VARIABLE "MODEL"
; 14. GET VALUE FROM STEP 10, MULTIPLY IT BY 16, ADD VALUE FROM STEP 13 AND ADD 1 MORE
; 15. READ STREAM OF BITS FROM MODEL #2
; 16. IF VALUE FROM STEP 14 > 800h, ADD 1 TO VALUE FROM STEP 15
; 17. IF VALUE FROM STEP 14 > 60h, ADD 1 TO VALUE FROM STEP 15
; 18. SET VARIABLE "OLD_DISPLACEMENT" TO VALUE FROM STEP 14
; 18. COPY BYTES THAT WERE IN OUTPUT BEFORE BY STEP 14, LENGTH IS EQUAL TO NUMBER FROM STEP 15
; 19. GO TO STEP 2

byte_decompression:
	MOV EBX, [EBP + model_0_pointer - data_for_decompressor]			; GET 0-TH MODEL
	CALL read_symbol_from_model_EBX
	STOSB										; SAVE BYTE

	OR ECX, -1									; ECX = -1: SPECIAL FLOW IS MODEL 3RD

check_special_flow:
	MOV EBX, [EBP + 4 * ECX + model_4_pointer - data_for_decompressor]		; GET 3RD/4TH MODEL
											; MODEL 3RD: NORMAL/SPECIAL FLOW AFTER NORMAL BYTE
											; MODEL 4TH: NORMAL/SPECIAL FLOW AFTER SPECIAL FLOW

	CALL read_symbol_from_model_EBX							; 3RD/4TH MODEL GIVES ONLY TWO VARIANTS:
											; 0 = NORMAL BYTE NEXT
											; 1 = ALL SPECIAL STUFF
	JZ byte_decompression								; IF == 0 --> CONTINUE NORMAL FLOW

	MOV ESI, read_bits_in_cycle
	JECXZ copy_previous_displacement_and_size

	MOV EBX, [EBP + model_7_pointer - data_for_decompressor]			; GET MODEL 7
	CALL read_symbol_from_model_EBX							; 7TH MODEL GIVES 2 VARIANTS
	JZ copy_previous_displacement_and_size						; 0 = COPY BYTES WITH COMPUTED SIZE FROM COMPUTED DISPLACEMENT
											; 1 = COPY BYTES WITH COMPUTED SIZE FROM OLD DISPLACEMENT

copy_previous_displacement:
	MOV EBX, [EBP + model_2_pointer - data_for_decompressor]			; GET MODEL 2
	CALL ESI									; READ COUNTER IN ECX
	MOV EAX, [EBP + displacement - data_for_decompressor]				; GET OLD DIPLACEMENT IN EAX
	JMP copy_from_previous_data

copy_previous_displacement_and_size:
	MOV EBX, [EBP + model_1_pointer - data_for_decompressor]
	CALL ESI									; GET HIGH NIBBLE OF COPY DISPLACEMENT IN ECX
	DEC ECX
	DEC ECX
	JS end_unpack									; MODEL 1 RESULT: 1 ==> UNPACKING ENDS
	SHL ECX, 4									; MOVE TO HIGH NIBBLE

	MOV EBX, [EBP + model_5_pointer - data_for_decompressor]
	JZ get_low_nibble
	SUB EBX, 4Ch									; MODEL 1 RESULT: 2 ==> REVERT FROM MODEL 5 TO MODEL 6

get_low_nibble:
	CALL read_symbol_from_model_EBX							; GET LOW NIBBLE OF COPY DISPLACEMENT IN ECX
	ADD EAX, ECX
	INC EAX										; TOTAL COPY DISPLACEMENT IN EAX

	MOV EBX, [EBP + model_2_pointer - data_for_decompressor]
	CALL ESI									; GET COPY SIZE IN ECX

	CMP EAX, 800h
	SBB ECX, -1									; IF DISPLACEMENT > 800h, ADD 1 TO COPY SIZE

	CMP EAX, 60h									; IF DISPLACEMENT > 60h, ADD 1 TO COPY SIZE
	SBB ECX, -1

copy_from_previous_data:
	MOV [EBP + displacement - data_for_decompressor], EAX				; SAVE NEW DISPLACEMENT

	MOV ESI, EDI
	SUB ESI, EAX
	REP MOVSB									; MOVE FROM ESI-[displacement] TO ESI, LEN = ECX
	JMP check_special_flow								; ECX = 0

end_unpack:

	MOV ESI, output_data_pointer + import_offset_in_output
	MOV EBX, load_library
	PUSH EBP

next_library:
	INC ESI
	LODSD								; POINTER TO LIST OF IMPORT ADDRESSES (FOR NOW: ALL OF THEM ARE EMPTY)
									; ESI POINTS NOW TO LIBRARY NAME
	TEST EAX, EAX
	JZ end_imports_set

	XCHG EAX, EDI

	PUSH ESI							; LIBRARY NAME
	CALL dword [EBX]						; LOAD LIBRARY
	TEST EAX, EAX
	JZ get_imports_error						; LIBRARY LOADING ERROR?

	XCHG EAX, EBP							; EBP: LIBRARY ADDR

read_library_name:
	LODSB
	TEST AL, AL
	JNZ read_library_name

	CMP [ESI], AL							; NO IMPORT FUNCTION NAMES LEFT?
	JZ next_library
	JS import_by_ordinal						; IF NOT NAME BUT ORDINAL

	PUSH ESI							; PARAMETER: IMPORT FUNCTION NAME

get_function_address:
	PUSH EBP							; PARAMETER: LIBRARY BASE ADDRESS
	CALL dword [EBX + 4]						; GET PROC ADDRESS
	STOSD								; SAVE FUNCTION ADDRESS

	TEST EAX, EAX							; WE GOT ADDRESS?
	JNZ read_library_name						; IF YES, MOVE TO NEXT FUNCTION
									; FUNCTION ADDRESS GETTING ERROR
get_imports_error:
	INC EAX
	POP EBX
	RET								; JMP TO PROGRAM WITHOUT IMPORTING ALL FUNCTIONS?
									; WELL, IT CERTAINLY WILL NOT WORK
									; BUT... WHAT CAN WE DO? NOTHING.
import_by_ordinal:
	INC ESI
	XOR EAX, EAX
	LODSW								; READ ORDINAL
	PUSH EAX							; STORE IT
	JMP get_function_address

end_imports_set:
	POP EBP
	RET								; JMP TO FIRST BYTE OF UNPACKED IMAGE

read_symbol_from_model_EBX:
	MOV EAX, [EBP + range - data_for_decompressor]					; GET RANGE
	XOR EDX, EDX
	DIV dword [EBX]									; DIVIDE BY TOTAL FREQUENCY
	MOV [EBP + range_per_one_frequency - data_for_decompressor], EAX		; REUSE RANGE VARIABLE

	MOV EAX, [EBP]									; GET POINTER TO INPUT STREAM
	MOV EAX, [EAX]									; GET DWORD FROM INPUT STREAM
	BSWAP EAX									; JUST CHANGE BIT ORDER
											; WAY FOR IMPROVEMENT: WE CAN SWAP IT DURING COMPRESSION ITSELF
	SUB EAX, [EBP + base - data_for_decompressor]					; SUBSTRACT "BASE" TO START INTERVAL FROM ZERO
	XOR EDX, EDX
	DIV dword [EBP + range_per_one_frequency - data_for_decompressor]		; HOW MANY "RANGES" INPUT STREAM CODES
	MOV [EBP + ranges_count - data_for_decompressor], EAX				; TEMPORARILY STORE RANGES COUNT

	XOR EDX, EDX									; CURRENT SYMBOL NUMBER

next_symbol:
	INC EDX										; TRY NEXT SYMBOL
	SUB EAX, [EBX + 4 * EDX]							; SUBSTRACT CURRENT SYMBOL FREQUENCY
	JNS next_symbol									; IF THIS IS NOT OUR NEXT SYMBOL

											; WE HAVE OUR "NEXT SYMBOL CODE + 1" IN EDX AS WE
											; START EDX FROM 1, NOT FROM 0
	PUSHA
	MOV ESI, EDX
	MOV EDX, [EBX + 4 * ESI]							; GET OUR SYMBOL FREQUENCY (F)
	INC EDX
	INC EDX										; F + 2 (IT SEEMS EVERY NEW BYTE ADDS 2 TO
											; FREQUENCY, NOT 1)
	XCHG EDX, [EBX + 4 * ESI]							; EDX = OLD CURRENT SYMBOL FREQUENCY
											; MEMORY = NEW CURRENT SYMBOL FREQUENCY

											; EAX = RANGES COUNT FOR NEXT SYMBOL AFTER OURS
											; EDX = OLD TOTAL FREQUENCY
 
	ADD EAX, EDX									; EAX = RANGES COUNT FROM "MINIMUM RANGE FOR
											; CURRENT SYMBOL" TO "ENCOUNTERED RANGE IN INPUT STREAM"
	NEG EAX										; EAX = MINUS "EAX"
	ADD EAX, [EBP + ranges_count - data_for_decompressor]				; EAX = MINIMUM VALUE FOR CURRENT SYMBOL
											; MEASURED IN RANGES (CUMULATIVE FREQUENCY)
	IMUL EAX, [EBP + range_per_one_frequency - data_for_decompressor]		; EAX = CUMULATIVE INTERVAL OFFSET FOR CURRENT SYMBOL
	ADD EAX, [EBP + base - data_for_decompressor]					; ADDING BASE --> NEW BASE

	IMUL EDX, [EBP + range_per_one_frequency - data_for_decompressor]		; EDX = NEW RANGE

check_base_range_size:
	LEA ESI, [EAX + EDX]								; NEW BASE + NEW RANGE
	XOR ESI, EAX									; XOR BASE
	CMP ESI, 01000000h
	JB enlarge_range								; IF UPPER 8 BIT OF BASE + RANGE ARE THE SAME
											; THAT MEANS RANGE IS TOO LOW - NEED TO ENLARGE IT

	CMP EDX, 00010000h								; RANGE TOO LOW?
	JNB check_for_threshold								; IF NOT

											; WE HAVE:
											; 1) "BASE" AND "BASE + RANGE" HAVE DIFFERENT UPPER BYTES.
											; IF NOT - WE WOULD HAVE CAPTURED IT ABOVE WITH 'JB'
											; 2) "RANGE" IS TOO LOW.
											; SO IT IS A SITUATION WHEN WE ARE NEAR xxFFFFFFh BASE
											; I.E. BASE: 55FFFF00h, RANGE = 4000h
											; SO BASE + RANGE = 56003F00h
											; WE CANNOT:
											; 1) OUTPUT BYTE TO OUTPUT AND SCALE BECAUSE
											; WE DON'T KNOW IF IT 55h OR 56h
											; 2) JUST ENLARGE RANGE PER SE.
											; SO WE DO A CLEVER TRICK. IN SUCH SITUATIONS
											; (BASE IS 55FFFF00h / RANGE 4000h), WE REPLACE RANGE
											; TO EVEN LESS(!) VALUE - 0100h.
											; BUT THEN WE WILL HAVE 55FFFF00h - 55FFFFFFh INCLUSIVE
											; AND... WE FINALLY CAN OUTPUT FIRST 55h BYTE AND
											; DO ENLARGE AS USUAL. 

	MOVZX EDX, AX									; GET LAST 16 BITS OF NEW BASE
	NEG DX										; WE THREAT DX AS UNSIGNED HERE - SO
											; DX = HOW MANY BYTES ARE FROM LAST 16 BIT OF NEW BASE
											; TO NEXT "BEAUTIFUL" ADDRESS
enlarge_range:
	INC dword [EBP]									; TO NEXT BYTE IN INPUT STREAM
	SHL EAX, 8									; MOVE BASE TO NEXT BYTE
	SHL EDX, 8									; MOVE RANGE TO NEXT BYTE
	JMP check_base_range_size

check_for_threshold:
	MOV [EBP + base - data_for_decompressor], EAX
	MOV [EBP + range - data_for_decompressor], EDX

	MOV EDX, [EBX]									; TOTAL FREQUENCY
	INC EDX
	INC EDX										; AS STATED BEFORE, EVERY BYTE ADDS 2 TO TOTAL
											; FREQUENCY, NOT 1
	CMP EDX, [EBX - 4]								; MORE THAN THRESHOLD FOR CURRENT MODEL?
	JB after_threshold								; IF NOT - RETURN

	XOR EAX, EAX

halve_next_symbol:
	INC EAX										; STARTING FROM SYMBOL NUMBER 0
	MOV ECX, [EBX + 4 * EAX]							; GET CURRENT SYMBOL FREQUENCY
	JECXZ after_threshold								; IF IT IS ZERO - THEN ALL SYMBOLS ARE HALVED
											; THIS IS DIVIDER OF OUR MODEL FROM NEXT
	SHR ECX, 1									; DIVIDE BY 2
	SUB [EBX + 4 * EAX], ECX							; REMOVE HALF-FREQUENCY

	SUB EDX, ECX									; REMOVE FROM TOTAL FREQUENCIES
	JMP halve_next_symbol

after_threshold:
	MOV [EBX], EDX									; NEW TOTAL FREQUENCIES

	POPA
	XCHG EAX, EDX									; EAX = READ SYMBOL + 1
	DEC EAX										; REMOVE 1
	RET										; RETURN READ SYMBOL

read_bits_in_cycle:
	XOR ECX, ECX
	INC ECX										; ECX = 1

	PUSH EAX

read_next_bit:
	CALL read_symbol_from_model_EBX							; READ TWO BITS:
											; 00: ADD BIT 0 TO RESULT, END
											; 01: ADD BIT 1 TO RESULT, END
											; 10: ADD BIT 0 TO RESULT, REPEAT
											; 11: ADD BIT 1 TO RESULT, REPEAT

	SHR EAX, 1
	ADC ECX, ECX									; READ ONE BIT IN ECX

	DEC EAX
	JNS read_next_bit

	POP EAX
	RET

models_info:
	DB 16, 1				; MODEL #7: THRESHOLD: 128, 2 SYMBOLS
	DB 48, 15				; MODEL #6: THRESHOLD: 384, 16 SYMBOLS
	DB 16, 15				; MODEL #5: THRESHOLD: 128, 16 SYMBOLS
	DB 8, 1					; MODEL #4: THRESHOLD: 64, 2 SYMBOLS
	DB 8, 1					; MODEL #3: THRESHOLD: 64, 2 SYMBOLS
	DB 24, 3				; MODEL #2: THRESHOLD: 192, 4 SYMBOLS
	DB 48, 3				; MODEL #1: THRESHOLD: 384, 4 SYMBOLS
	DB 128, 255				; MODEL #0: THRESHOLD: 1024, 256 SYMBOLS: LITERAL BYTE MODEL

kernel32_imports:
load_library:		DD loadlibrary_name - image_base		; WILL BE POPULATED BY IMPORT ADDRESS
get_proc_address:	DD getprocaddress_name - image_base		; WILL BE POPULATED BY IMPORT ADDRESS

	DB 4 DUP(0)

kernel32_name:
	DB 'KERNEL32.DLL'
loadlibrary_name:
	DB 0, 0
	DB 'LoadLibraryA'
getprocaddress_name:
	DB 0, 0
	DB 'GetProcAddress'
	DB 0, 0

	DD kernel32_imports - image_base		; IMPORT NAME TABLE
	DD 0						; TIMESTAMP
	DD 0						; FORWARDER CHAIN
	DD kernel32_name - image_base			; DLL NAME
	DD kernel32_imports - image_base		; IMPORT ADDRESS TABLE

	DB 21 DUP(0)

virtual at 7D7C08h

data_for_decompressor:

input_stream:	DD ?				; POINTER TO INPUT STREAM

base:		DD ?				; BASE OF OUR interval:
						; IT IS [base; base + range]
						; BUT WE PRETEND IT IS [0; range]
range:
range_per_one_frequency:			; VARIABLE USED FOR BOTH PURPOSES
		DD ?

displacement:	DD ?				; FOR COPYING OLD DATA TO NEW DATA

ranges_count:	DD ?				; TEMPORARY SPACE FOR RANGES COUNT

model_0_pointer:	DD ?			; WILL POINT TO _model_0
						; LITERAL COMPRESSOR (OUTPUT BYTES)
model_1_pointer:	DD ?			; WILL POINT TO _model_1
						; USED TO READ HIGH NIBBLE OF DISPLACEMENT FOR LZ77 MOVES
						; SPECIAL CASE: VALUE 1 - END OF UNPACK
						; SPECIAL CASE: VALUE 2 - DISPLACEMENT CONSIDERED "NEAR", NOT FAR
model_2_pointer:	DD ?			; WILL POINT TO _model_2
						; USED TO READ LENGTH FOR LZ77 MOVES
model_3_pointer:	DD ?			; WILL POINT TO _model_3
						; LZ77 COMPRESSOR - OUTPUT EITHER 0 (NORMAL BYTE) OR 1 (SPECIAL CASE). USED AFTER NORMAL CASE (MODEL #0)
model_4_pointer:	DD ?			; WILL POINT TO _model_4
						; LZ77 COMPRESSOR - OUTPUT EITHER 0 (NORMAL BYTE) OR 1 (SPECIAL CASE). USED ONLY AFTER SPECIAL CASE.
model_5_pointer:	DD ?			; WILL POINT TO _model_5
						; USED TO READ LOW NIBBLE OF DISPLACEMENT FOR LZ77 MOVES FOR FAR DISPLACEMENTS
model_6_pointer:	DD ?			; WILL POINT TO _model_6
						; USED TO READ LOW NIBBLE OF DISPLACEMENT FOR LZ77 MOVES FOR NEAR DISPLACEMENTS
model_7_pointer:	DD ?			; WILL POINT TO _model_7
						; OUTPUT EITHER 0 IF WE NEED TO GET SIZE/DISPLACEMENT FOR LZ77 OR 1 - IF WE NEED ONLY SIZE
models:

	DD ?					; WILL BE 0
	DD ?					; WILL BE 128 - THRESHOLD FOR MODEL #7
_model_7:
	DD ?					; TOTAL FREQUENCY MODEL #7 - INITIALLY 2, THEN MORE
	DD 2 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #7

	DD ?					; WILL BE 0
	DD ?					; WILL BE 384 - THRESHOLD FOR MODEL #6
_model_6:
	DD ?					; TOTAL FREQUENCY FOR MODEL #6 - INITIALLY 16, THEN MORE
	DD 16 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #6

	DD ?					; WILL BE 0
	DD ?					; WILL BE 128 - THRESHOLD FOR MODEL #5
_model_5:
	DD ?					; TOTAL FREQUENCY FOR MODEL #5 - INITIALLY 16, THEN MORE
	DD 16 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #5

	DD ?					; WILL BE 0
	DD ?					; WILL BE 64 - THRESHOLD FOR MODEL #4
_model_4:
	DD ?					; TOTAL FREQUENCY FOR MODEL #4 - INITIALLY 2, THEN MORE
	DD 2 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #4

	DD ?					; WILL BE 0
	DD ?					; WILL BE 64 - THRESHOLD FOR MODEL #3
_model_3:
	DD ?					; TOTAL FREQUENCY FOR MODEL #3 - INITIALLY 2, THEN MORE
	DD 2 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #3

	DD ?					; WILL BE 0
	DD ?					; WILL BE 192 - THRESHOLD FOR MODEL #2
_model_2:
	DD ?					; TOTAL FREQUENCY FOR MODEL #2 - INITIALLY 4, THEN MORE
	DD 4 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #2

	DD ?					; WILL BE 0
	DD ?					; WILL BE 384 - THRESHOLD FOR MODEL #1
_model_1:
	DD ?					; TOTAL FREQUENCY FOR MODEL #1 - INITIALLY 4, THEN MORE
	DD 4 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #1

	DD ?					; WILL BE 0
	DD ?					; WILL BE 1024 - THRESHOLD FOR MODEL #0
_model_0:
	DD ?					; TOTAL FREQUENCY FOR MODEL #0 - INITIALLY 256, THEN MORE
	DD 256 DUP(?)				; SYMBOL FREQUENCIES FOR MODEL #0

end virtual
