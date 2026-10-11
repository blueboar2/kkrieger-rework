format binary
use32
include 'INCLUDE/win32a.inc'

image_base = 007C0000h

output_data_pointer = 00801000h
program_entry_point = 00805427h

org 7E3DA9h

; At the beginning of second unpacking step some registers are already initialized after
; the first unpacking step, namely:
; EBP is pointing to the the same area of memory that was used for decompressor temporary
; data. It was named "data_for_decompressor" in the first step, but now it is reused for
; another data
; ESI is pointing to the first dword after imports, namely "segments_tables" in this program.
; It is pointer to different tables that were packed independently and needs to be
; assembled again

entry_point:
	MOV EDI, output_data_pointer
	MOV EBX, EDI
	DB 81h, 0EBh, 4, 0, 0, 0					; SUB EBX, 4
									; DON'T KNOW WHY THIS LONG WAY, BECAUSE
									; BY DEFAULT FASM USES 83h, 0EBh, 4

	MOV [EBP + starting_addr - data_for_part_2], EBX		; STARTING ADDRESS (-4) POINTER
	XOR EAX, EAX
	MOV [EBP + last_jump - data_for_part_2], EAX			; LAST JMP IS ZERO
	INC EAX
	MOV [EBP + next_function - data_for_part_2], EAX		; NEXT BYTE IS A START OF A FUNCTION
	MOV [EBP + function_table_position - data_for_part_2], EAX	; NEXT FUNCTION WILL BE FIRST IN A TABLE

	LEA EBX, [ESI + input_data - segments_tables]			; OFFSET TO INPUT_DATA FROM STARTING ESI VALUE
	XOR ECX, ECX							; STARTING SIZE

next_segment:
	LODSD								; GET SIZE OF NEXT SEGMENT
	MOV [EBP + 4 * ECX + 0], EBX					; STORE STARTING ADDRESS TO TABLE
	ADD EBX, EAX							; ADD SEGMENT SIZE
	INC ECX								; TO NEXT SEGMENT
	CMP CL, 15h							; ALL SEGMENTS?
	JNZ next_segment

	MOV ESI, [EBP + eax_disp8_offset - data_for_part_2]
	XCHG ESI, [EBP + main_code_offset - data_for_part_2]		; NOW ESI IS STARTING ADDRESS (main_code)
									; [MAIN_CODE] IS OFFSET TO SECOND SEGMENT
									; SO WE WILL USE IT TO CHECK IF THE DECODING ENDS
decode_next_part:
	CMP ESI, [EBP + main_code_offset - data_for_part_2]		; WE ALREADY DECODE EVERYTHING?
	JZ program_entry_point						; IF YES, THEN JMP TO ENTRY POINT

	XOR EAX, EAX
	CMP [EBP + next_function - data_for_part_2], EAX		; WE CAN HAVE NEXT FUCTION START?
	LODSB								; GET NEXT BYTE
	JZ check_for_escape						; IF NOT, SKIP UPDATING FUNCTIONS TABLE

	CMP AL, 0CCh							; INT3?
	JZ check_for_escape						; IF YES, SKIP UPDATING FUCTIONS TABLE, AS
									; IT IS PADDING, FUNCTION IS NOT YET STARTED

	LEA ECX, [EDI - 4]						; GET CURRENT OUTPUT POSITION
	SUB ECX, [EBP + starting_addr - data_for_part_2]		; SUBTRACT STARTING OUTPUT ADDR

	MOV EBX, [EBP + function_table_position - data_for_part_2]	; GET CURRENT FUNCTION NUMBER
	MOV [EBP + 4 * EBX + function_table_position - data_for_part_2], ECX	; SAVE FUNCTION OFFSET

make_not_zero:
	INC byte [EBP + function_table_position - data_for_part_2]	; MOVE TO NEXT FUNCTION IN A BUFFER IN CIRCULAR MANNER
	JZ make_not_zero						; EXCEPT ZERO

	MOV byte [EBP + next_function - data_for_part_2], 0		; FLAG: WE DO NOT HAVE NEXT FUNCTION START NOW

check_for_escape:
	CMP AL, 0CEh							; ORIGINALLY: INTO INSTRUCTION, BUT USED HERE AS ESCAPE
									; SYMBOL. IT MEANS: JUST MOVE ONE BYTE AFTER THIS SYMBOL
									; AS-IS WITHOUT THINKING
	JNZ check_operand_size

	MOVSB								; BYTE 0CEh MEANS - JUST MOVE ONE BYTE
	JMP decode_next_part

check_operand_size:
	STOSB								; MOVE FIRST BYTE (OPCODE) TO OUTPUT

	XOR EDX, EDX							; DH = 0: FLAG: 32-BIT OPERAND
	CMP AL, 66h							; 16-BIT OPERAND SIZE PREFIX?
	JNZ check_for_ret

	MOV DH, 1							; DH = 1: FLAG: 16-BIT OPERAND

	LODSB
	STOSB								; IF YES, MOVE SECOND BYTE (OPCODE) TO OUTPUT (66 + OPCODE CASE)

check_for_ret:

	MOV BL, AL
									; CHECK FOR 0C2h (RETN) or 0C3h (RET)
	SUB BL, 0C2h							; CASE #1: BL WAS < 0C2H, WILL BE UNDERFLOWED, AND > 1
									; CASE #2: BL WAS 0C2H - WILL BE 0
									; CASE #3: BL WAS 0C3H - WILL BE 1
									; CASE #4: BL WAS > 0C3H, WILL BE > 1
	CMP BL, 1							; CHECK ONLY FOR C2/C3							
	JA check_0f_instruction

	MOV byte [EBP + next_function - data_for_part_2], 1		; IF WE ENCOUNTERED RET/RETN - PROBABLY WE WOULD FIND
									; NEXT FUNCTION AS NEXT COMMAND

check_0f_instruction:
	MOV EBX, disasm_first_byte_meaning_normal

	CMP AL, 0Fh							; CHECK FOR 0F OPCODE (EXTENDED INSTRUCTIONS)
	JNZ lookup_table

	LODSB
	STOSB								; IF YES, MOVE REAL OPCODE TO OUTPUT

	MOV AH, 1							; SWITCH TABLE TO EXTENDED INSTRUCTIONS TABLE

lookup_table:

	SHR EAX, 1							; ONE ENTRY IN TABLE MEANS TWO COMMANDS
	XLAT byte [EBX]							; GET VALUE FROM TABLE
	JNB test_modrm							; GET LOWER 4 BITS
	SHR AL, 4							; OR UPPER 4 BITS DEPENDENT ON EVEN/ODD OPCODE

	
test_modrm:
	AND AL, 0Fh							; GET ONLY 4 BITS
	MOV CL, AL
	TEST CL, 2							; IS THERE MODRM BYTE?
	JZ near check_address						; IF NOT
									; IF YES
									; DON'T KNOW WHY LONG VERSION OF JZ WAS USED
									; YOU CAN PERFECTLY USE SHORT ONE

	LODSB
	STOSB								; MOVE IT TO THE OUTPUT

	MOV CH, AL							; CH = READ MODRM BYTE
	MOV AL, CL							; AL = VALUE FROM TABLE

	AND AL, 3
	CMP AL, 3							; MODRM + EXTRA OPCODE (F6, F7, FE, FF)?
	JNZ check_for_SIB_byte						; IF NOT

	MOV CL, 2							; IF THIS IS F6/F7/FE/FF, SET TO JUST MODRM

	TEST CH, 38H							; F6/F7/FE/FF
	JNZ check_for_SIB_byte                                          ; ALL COMMANDS EXCEPT
									; 1) F6/0: TEST R/M8, IMM8
									; 2) F7/0: TEST R/M16/M32, IMM16/IMM32
									; 3) FE/0: INC R/M8
									; 4) FF/0: INC R/M16/M32

	MOV BL, [EDI - 2]						; GET INSTRUCTION CODE (F6/F7/FE/FF)
									; EDI POINTS TO NEXT EMPTY PLACE IN OUTPUT
									; EDI - 1 POINTS TO MODRM BYTE
									; EDI - 2 POINTS TO INSTRUCTION CODE (F6/F7/FE/FF)
	TEST BL, 8
	JNZ check_for_SIB_byte						; FE/FF: INC R/M8 OR INC R/M16/M32
									; F6/F7: TEST R/M8, IMM8 OR TEST R/M16/M32, IMM32

	ADD CL, 4							; IF THIS IS TEST COMMAND --> + IMM8
									; SEEMS ERROR AS F7/0 SHOULD ADD IMM32, NOT IMM8

check_for_SIB_byte:
									; SIB BYTE CAN BE IF
									; - MOD != 11 + R/M == 100 (SIB)

	AND CH, 0C7h							; GET ONLY MOD AND R/M

	CMP CH, 0C4h
	JZ check_disp8							; IF MOD == 11 / R/M == 100 --> NOT OUR CASE

									; CASE 1: MOD == 11 / R/M != 100
									; CASE 2: MOD != 11 / R/M CAN BE ANYTHING

	MOV AL, CH
	AND AL, 7							; CHECK FOR R/M
	CMP AL, 4
	JNZ check_disp8							; IF R/M != 100 --> NOT OUR CASE

									; ONLY MOD != 11 / R/M == 100
	MOVSB								; MOVE SIB BYTE

check_disp8:
        MOV DL, CH							; GET MODRM
	AND DL, 0C0h							; GET ONLY MOD
	CMP DL, 40H							; CHECK MOD == 01 (DISP8)
	JNZ check_disp32						; IF NOT - SKIP

	MOVZX EBX, CH
	AND BL, 7							; GET ONLY R/M

	XCHG ESI, [EBP + 4 * EBX + eax_disp8_offset - data_for_part_2]
	MOVSB								; MOVE DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + 4 * EBX + eax_disp8_offset - data_for_part_2]

check_disp32:
	CMP DL, 80h
	JZ disp32_found							; CHECK MOD == 10 (DISP32)

	CMP CH, 5							; CH = MOD + R/M
	JZ disp32_found							; CHECK MOD == 00 / R/M == 101: DISP32

	TEST DL, DL
	JNZ check_address						; CHECK MOD == 01/11

									; MOD == 00
	MOV AL, [ESI - 1]						; SIB BYTE
	AND AL, 7
	CMP AL, 5
	JNZ check_address						; CHECK SIB = xxxxx101: DISP32

disp32_found:
	XOR EBX, EBX
	CMP CH, 5
	JNZ apply_disp32

	INC EBX								; CASE MOD == 00 / R/M == 101
									; I.E. MOV EAX, [12345678]
									; CHANGE SEGMENT
apply_disp32:
	XCHG ESI, [EBP + 4 * EBX + disp32_reg_offset_3_byte - data_for_part_2]
	LODSD								
	DEC ESI								; GET 3 BYTE OF DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + 4 * EBX + disp32_reg_offset_3_byte - data_for_part_2]

	XCHG ESI, [EBP + disp32_offset_fourth_byte - data_for_part_2]
	SHL EAX, 8
	LODSB								; GET 4TH BYTE OF DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_offset_fourth_byte - data_for_part_2]
	ROR EAX, 8
	STOSD

check_address:
	MOV AL, CL							; VALUE FROM TABLE
	AND AL, 3
	CMP AL, 1							; ADDRESS
	JNZ check_imm_8_16_32						; IF NOT

	SHR CL, 2
	JNZ imm8_or_call_jmp_addr					; IF BYTE RELATIVE OR CALL/JMP
									; IF DWORD RELATIVE

	XCHG ESI, [EBP + disp32_address_3_byte - data_for_part_2]
	LODSD								
	DEC ESI								; GET 3 BYTE OF DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_address_3_byte - data_for_part_2]

	XCHG ESI, [EBP + disp32_address_fourth_byte - data_for_part_2]
	SHL EAX, 8
	LODSB								; GET 4TH BYTE OF DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_address_fourth_byte - data_for_part_2]
	ROR EAX, 8
	STOSD

	JMP decode_next_part

imm8_or_call_jmp_addr:
	DEC CL
	JNZ call_or_jmp_addr						; IF CALL/JMP
									; IF NOT

	XCHG ESI, [EBP + disp8_address - data_for_part_2]
	MOVSB								; GET 1 BYTE OF DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp8_address - data_for_part_2]
	JMP decode_next_part

call_or_jmp_addr:
	XOR EBX, EBX
	CMP BYTE [EDI - 1], 0E8h					; CALL?
	JZ check_call_function_number					; IF CALL
									; IF JMP
	
	XCHG ESI, [EBP + disp32_jump_call_high_delta - data_for_part_2]
	LODSW								; GET 2 HIGHER BYTES OF DELTA DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_jump_call_high_delta - data_for_part_2]

	XCHG ESI, [EBP + disp32_jump_low_delta - data_for_part_2]
	SHL EAX, 16
	LODSW								; GET 2 LOWER BYTES OF DELTA DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_jump_low_delta - data_for_part_2]

	SHR EAX, 1
	JNB skip_not							; IF LAST BYTE = 0, ADD TO PREVIOUS DISPLACEMENT
									; ELSE SUBSTRACT FROM PREVIOUS DISPLACEMENT

	NOT EAX

skip_not:
	ADD EAX, [EBP + last_jump - data_for_part_2]
	MOV [EBP + last_jump - data_for_part_2], EAX			; STORE NEW DISPLACEMENT
	JMP save_address

check_call_function_number:
	XOR EAX, EAX

	XCHG ESI, [EBP + call_func_number_or_low_delta - data_for_part_2]
	LODSB								; GET BYTE FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + call_func_number_or_low_delta - data_for_part_2]

	TEST AL, AL
	JZ call_real_displacement					; 0 MEANS SOME NEW FUNCTION


	MOV EAX, [EBP + 4 * EAX + function_addresses - 4 - data_for_part_2]	; ELSE GET FUNCTION OFFSET
	JMP save_address

call_real_displacement:
	XCHG ESI, [EBP + disp32_jump_call_high_delta - data_for_part_2]
	LODSW								; GET 2 HIGHER BYTES OF DELTA DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + disp32_jump_call_high_delta - data_for_part_2]

	XCHG ESI, [EBP + call_func_number_or_low_delta - data_for_part_2]
	SHL EAX, 16
	LODSW								; GET 2 LOWER BYTES OF DELTA DISPLACEMENT FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + call_func_number_or_low_delta - data_for_part_2]

	MOV EBX, [EBP + function_table_position - data_for_part_2]
	MOV [EBP + 4 * EBX + function_table_position - data_for_part_2], EAX

skip_function_0:
	INC BYTE [EBP + function_table_position - data_for_part_2]	; SAVE CALL TARGET AS NEXT FUNCTION
	JZ skip_function_0

save_address:
	SUB EAX, EDI							; DISPLACEMENT - STARTING ADDRESS
	ADD EAX, [EBP + starting_addr - data_for_part_2]		; ADD REAL STARTING ADDRESS
	STOSD
	JMP decode_next_part

check_imm_8_16_32:
	SHR CL, 2
	JZ decode_next_part						; IF NO IMM8/IMM16/IMM32

	DEC CL
	JNZ check_imm_16_32						; IMM16/IMM32
									; IMM8

	XCHG ESI, [EBP + imm_8 - data_for_part_2]
	MOVSB								; MOVE IMM8 FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + imm_8 - data_for_part_2]
	JMP decode_next_part

check_imm_16_32:
	DEC CL
	JNZ imm16							; IF NOT IMM32

	TEST DH, DH							; TEST 66H PREFIX
	JNZ imm16							; IF YES, THEN IMM16, NOT IMM32

	XCHG ESI, [EBP + imm_32 - data_for_part_2]
	MOVSD								; MOVE IMM32 FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + imm_32 - data_for_part_2]
	JMP decode_next_part

imm16:
	XCHG ESI, [EBP + imm_16 - data_for_part_2]
	MOVSW								; MOVE IMM16 FROM CORRESPONDING SEGMENT
	XCHG ESI, [EBP + imm_16 - data_for_part_2]
	JMP decode_next_part

disasm_first_byte_meaning_normal:
; Here we assume we are in 32-bit IMM. 16-bit IMM will be checked after consulting this table in the code

	DB 22H						; OPCODE 00: ADD R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 01: ADD R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 02: ADD R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 03: ADD R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 04: ADD AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 05: ADD EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 06: PUSH ES: 00: NO MODRM + NO IMM
							; OPCODE 07: POP ES: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 08: OR R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 09: OR R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0A: OR R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 0B: OR R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 0C: OR AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 0D: OR EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 0E: PUSH CS: 00: NO MODRM + NO IMM
							; OPCODE 0F: CHECKED IN THE CODE EXPLICITLY, WILL NOT OCCUR
	DB 22H						; OPCODE 10: ADC R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 11: ADC R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 12: ADC R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 13: ADC R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 14: ADC AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 15: ADC EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 16: PUSH SS: 00: NO MODRM + NO IMM
							; OPCODE 17: POP SS: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 18: SBB R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 19: SBB R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 1A: SBB R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 1B: SBB R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 1C: SBB AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 1D: SBB EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 1E: PUSH DS: 00: NO MODRM + NO IMM
							; OPCODE 1F: POP DS: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 20: AND R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 21: AND R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 22: AND R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 23: AND R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 24: AND AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 25: AND EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 26: ES SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
							; OPCODE 27: DAA: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 28: SUB R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 29: SUB R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 2A: SUB R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 2B: SUB R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 2C: SUB AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 2D: SUB EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 2E: CS SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
							; OPCODE 2F: DAS: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 30: XOR R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 31: XOR R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 32: XOR R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 33: XOR R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 34: XOR AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 35: XOR EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 36: SS SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
							; OPCODE 37: AAA: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 38: CMP R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 39: CMP R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 3A: CMP R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 3B: CMP R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 84H						; OPCODE 3C: CMP AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 3D: CMP EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE 3E: DS SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
							; OPCODE 3F: AAS: 00: NO MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 40-47: INC R32: 00: NO MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 48-4F: DEC R32: 00: NO MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 50-57: PUSH R32: 00: NO MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 58-5F: POP R32: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 60: PUSHA: 00: NO MODRM + NO IMM
							; OPCODE 61: POPA: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 62: BOUND R16/R32, M16/M32: 02: MODRM + NO IMM
							; OPCODE 63: ARPL R/M16, R16: 02: MODRM + NO IMM
	DB 00H						; OPCODE 64: FS SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
							; OPCODE 65: GS SEGMENT OVERRIDE: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 66: OPERAND SIZE PREFIX: 00: NO MODRM + NO IMM
							; OPCODE 67: ADDRESS SIZE PREFIX: 00: NO MODRM + NO IMM
	DB 0A8H						; OPCODE 68: PUSH IMM32: 08: NO MODRM + 4 BYTE IMM
							; OPCODE 69: IMUL R16/R32, R16/R32, IMM32: 0A: MODRM + 4 BYTE IMM
	DB 64H						; OPCODE 6A: PUSH IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE 6B: IMUL R16/R32, R16/R32, IMM8: 06: MODRM + 1 BYTE IMM
	DB 00H						; OPCODE 6C: INS M8, DX: 00: NO MODRM + NO IMM
							; OPCODE 6D: INS M16/32, DX: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 6E: OUTS DX, M8: 00: NO MODRM + NO IMM
							; OPCODE 6F: OUTS DX, M16/M32: 00: NO MODRM + NO IMM
	DB 8 DUP(55H)					; OPCODES 70-7F: Jxx REL8: 05: NO MODRM + ADDRESS MODE + 1 BYTE IMM
	DB 0A6H						; OPCODE 80: [MATH] R/M8, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE 81: [MATH] R/M16/M32, IMM32: 0A: MODRM + 4 BYTE IMM
	DB 66H						; OPCODE 82: [MATH] R/M8, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE 83: [MATH] R/M16/M32, IMM32: 06: MODRM + 1 BYTE IMM
	DB 22H						; OPCODE 84: TEST R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 85: TEST R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 86: XCHG R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 87: XCHG R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 88: MOV R/M8, R8: 02: MODRM + NO IMM
							; OPCODE 89: MOV R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 8A: MOV R8, R/M8: 02: MODRM + NO IMM
							; OPCODE 8B: MOV R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 8C: MOV M16/R16/R32, SREG: 02: MODRM + NO IMM
							; OPCODE 8D: LEA R16/R32, M: 02: MODRM + NO IMM
	DB 22H						; OPCODE 8E: MOV SREG, M16/R16: 02: MODRM + NO IMM
							; OPCODE 8F: POP R/M16/M32: 02: MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 90-97: XCHG R16/R32, EAX: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 98: ÑBW/CWDE: 00 NO MODRM + NO IMM
							; OPCODE 99: CWD/CDQ: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 9A: CALLF PTR16:16/32: 00 NO MODRM + NO IMM
							; OPCODE 9B: FWAIT: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 9C: PUSHF: 00 NO MODRM + NO IMM
							; OPCODE 9D: POPF: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 9E: SAHF: 00 NO MODRM + NO IMM
							; OPCODE 9F: LAHF: 00: NO MODRM + NO IMM
	DB 11H						; OPCODE A0: MOV AL, MOFF8: 01 NO MODRM + ADDRESS MODE
							; OPCODE A1: MOV EAX, MOFFS32: 01: NO MODRM + ADDRESS MODE
	DB 11H						; OPCODE A2: MOV MOFF8, AL: 01 NO MODRM + ADDRESS MODE
							; OPCODE A3: MOV MOFFS32, EAX: 01: NO MODRM + ADDRESS MODE
	DB 00H						; OPCODE A4: MOVSB: 00 NO MODRM + NO IMM
							; OPCODE A5: MOVSW/MOVSD: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE A6: CMPSB: 00 NO MODRM + NO IMM
							; OPCODE A7: CMPSW/CMPSD: 00: NO MODRM + NO IMM
	DB 84H						; OPCODE A8: TEST AL, IMM8: 04: NO MODRM + 1 BYTE IMM
							; OPCODE A9: TEST EAX, IMM32: 08: NO MODRM + 4 BYTE IMM
	DB 00H						; OPCODE AA: STOSB: 00 NO MODRM + NO IMM
							; OPCODE AB: STOSW/STOSD: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE AC: LODSB: 00 NO MODRM + NO IMM
							; OPCODE AD: LODSW/LODSD: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE AE: SCASB: 00 NO MODRM + NO IMM
							; OPCODE AF: SCASW/SCASD: 00: NO MODRM + NO IMM
	DB 4 DUP(44H)					; OPCODES B0-B7: MOV R8, IMM8: 04 NO MODRM + 1 BYTE IMM
	DB 4 DUP(88H)					; OPCODES B8-BF: MOV R16/R32, IMM32: 08 NO MODRM + 4 BYTE IMM
	DB 66H						; OPCODE C0: [SHIFT] R/M8, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE C1: [SHIFT] R/M16/M32, IMM8: 06: MODRM + 1 BYTE IMM
	DB 0CH						; OPCODE C2: RETN IMM16: 0C: NO MODRM + 2 BYTE IMM
							; OPCODE C3: RET: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE C4: LES R16/R32, M16:M32: 02: MODRM + NO IMM
							; OPCODE C5: LDS R16/R32, M16:M32: 02: MODRM + NO IMM
	DB 0A6H						; OPCODE C6: MOV R/M8, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE C7: MOV R/M16/M32, IMM32: 0A: MODRM + 4 BYTE IMM
	DB 00H						; OPCODE C8: ENTER EBP, IMM16, IMM8: 00 NO MODRM + NO IMM
							; SEEMS ERROR, HAS 3 BYTE IMM
							; OPCODE C9: LEAVE: 00: NO MODRM + NO IMM
	DB 0CH						; OPCODE CA: RETF IMM16: 0C: NO MODRM + 2 BYTE IMM
							; OPCODE CB: RETF: 00: NO MODRM + NO IMM
	DB 40H						; OPCODE CC: INT3: 09: NO MODRM + NO IMM
							; OPCODE CD: INT IMM8: 04: NO MODRM + 1 BYTE IMM
	DB 00H						; OPCODE CE: INTO: 00 NO MODRM + NO IMM
							; OPCODE CF: IRET: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE D0: [SHIFT] R/M8, 1: 02: MODRM + NO IMM
							; OPCODE D1: [SHIFT] R/M16/M32, 1: 02: MODRM + NO IMM
	DB 22H						; OPCODE D2: [SHIFT] R/M8, CL: 02: MODRM + NO IMM
							; OPCODE D3: [SHIFT] R/M16/M32, CL: 02: MODRM + NO IMM
	DB 44H						; OPCODE D4: AMX AL, AH, IMM8: 04 NO MODRM + 1 BYTE IMM
							; OPCODE D5: ADX AL, AH, IMM8: 04 NO MODRM + 1 BYTE IMM
	DB 00H						; OPCODE D6: SALC: 00 NO MODRM + NO IMM
							; OPCODE D7: XLAT: 00: NO MODRM + NO IMM
	DB 4 DUP(22H)					; OPCODES D8-DF: [FP87]: 02: MODRM + NO IMM
	DB 55H						; OPCODE E0: LOOPNZ REL8: 05: NO MODRM + ADDRESS MODE + 1 BYTE IMM
							; OPCODE E1: LOOPZ REL8: 05: NO MODRM + ADDRESS MODE + 1 BYTE IMM
	DB 55H						; OPCODE E2: LOOP REL8: 05: NO MODRM + ADDRESS MODE + 1 BYTE IMM
							; OPCODE E3: JCXZ REL8: 05: NO MODRM + ADDRESS MODE + 1 BYTE IMM
	DB 44H						; OPCODE E4: IN AL, IMM8: 04 NO MODRM + 1 BYTE IMM
							; OPCODE E5: IN EAX, IMM8: 04 NO MODRM + 1 BYTE IMM
	DB 44H						; OPCODE E6: OUT IMM8, AL: 04 NO MODRM + 1 BYTE IMM
							; OPCODE E7: OUT IMM8, EAX: 04 NO MODRM + 1 BYTE IMM
	DB 0DDH						; OPCODE E8: CALL REL16/32: 0D NO MODRM + ADDRESS MODE + 4 BYTE IMM
							; OPCODE E9: JMP REL16/32: 0D NO MODRM + ADDRESS MODE + 4 BYTE IMM
	DB 51H						; OPCODE EA: JMPF PTR16:ADDR16/32: 01 NO MODRM + ADDRESS MODE + 4 BYTE IMM
							; SEEMS ERROR AS NEED 6 BYTES IMM, NOT 4 BYTES
							; OPCODE EB: JMP REL8: 05 NO MODRM + ADDRESS MODE + 1 BYTE IMM
	DB 00H						; OPCODE EC: IN AL, DX: 00 NO MODRM + NO IMM
							; OPCODE ED: IN EAX, DX: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE EE: OUT DX, AL: 00 NO MODRM + NO IMM
							; OPCODE EF: OUT DX, EAX: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE F0: LOCK: 00 NO MODRM + NO IMM
							; OPCODE F1: INT1: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE F2: REPNZ: 00 NO MODRM + NO IMM
							; OPCODE F3: REPZ: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE F4: HLT: 00 NO MODRM + NO IMM
							; OPCODE F5: CMC: 00: NO MODRM + NO IMM
	DB 33H						; OPCODE F6: [MATH] R/M8, IMM8: 03 MODRM + EXTRA OPCODE
							; OPCODE F7: [MATH] R/M16/M32, IMM32: 03: MODRM + EXTRA OPCODE
	DB 00H						; OPCODE F8: CLC: 00 NO MODRM + NO IMM
							; OPCODE F9: STC: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE FA: CLI: 00 NO MODRM + NO IMM
							; OPCODE FB: STI: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE FC: CLD: 00 NO MODRM + NO IMM
							; OPCODE FD: STD: 00: NO MODRM + NO IMM
	DB 33H						; OPCODE FE: INC/DEC R/M8: 03 MODRM + EXTRA OPCODE
							; OPCODE FF: [CALL/JMP] R/M16/M32: 03: MODRM + EXTRA OPCODE

disasm_first_byte_meaning_0F:
	DB 8 DUP(00H)					; OPCODES 0F00-0F0F: VARIOUS INSTRUCTIONS: 00: NO MODRM + NO IMM
	DB 4 DUP(22H)					; OPCODES 0F10-0F17: VARIOUS SSE INSTRUCTIONS: 02: MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 0F18-0F1F: NOP: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 0F20: MOV R32, CRn: 02: MODRM + NO IMM
							; OPCODE 0F21: MOV R32, DRn: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0F22: MOV CRn, R32: 02: MODRM + NO IMM
							; OPCODE 0F23: MOV DRn, R32: 02: MODRM + NO IMM
	DB 6 DUP(00H)					; OPCODES 0F24-0F2F: VARIOUS SSE INSTRUCTIONS: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 0F30: WRMSR: 00 NO MODRM + NO IMM
							; OPCODE 0F31: RDTSC: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 0F32: RDMSR: 00 NO MODRM + NO IMM
							; OPCODE 0F33: RDPMC: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 0F34: SYSENTER: 00 NO MODRM + NO IMM
							; OPCODE 0F35: SYSEXIT: 00: NO MODRM + NO IMM
	DB 00H						; OPCODE 0F36: NONE: 00 NO MODRM + NO IMM
							; OPCODE 0F37: GETSEC: 00: NO MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 0F38-0F3F: VARIOUS SSE/NOP INSTRUCTIONS: 00: NO MODRM + NO IMM
	DB 8 DUP(22H)					; OPCODES 0F40-0F4F: CMOVxx: 02: MODRM + NO IMM
	DB 8 DUP(00H)					; OPCODES 0F50-0F5F: VARIOUS SSE: 00: NO MODRM + NO IMM
	DB 8 DUP(22H)					; OPCODES 0F60-0F6F: VARIOUS MMX: 02: MODRM + NO IMM
	DB 66H						; OPCODE 0F70: PSHUFxx: 06 MODRM + 1 BYTE IMM
							; OPCODE 0F71: VARIOUS MMX SHIFTS: 06: MODRM + 1 BYTE IMM
	DB 66H						; OPCODE 0F72: VARIOUS MMX SHIFTS: 06: MODRM + 1 BYTE IMM
							; OPCODE 0F73: VARIOUS MMX SHIFTS: 06: MODRM + 1 BYTE IMM
	DB 22H						; OPCODE 0F74: PCMPEQB: 02: MODRM + NO IMM
							; OPCODE 0F75: PCMPEQW: 02: MODRM + NO IMM
	DB 02H						; OPCODE 0F76: PCMPEQD: 02: MODRM + NO IMM
							; OPCODE 0F77: EMMS: 00: NO MODRM + NO IMM
	DB 3 DUP(00H)					; OPCODES 0F78-0F7D: VARIOUS SSE INSTRUCTIONS: 00: NO MODRM + NO IMM
	DB 22H						; OPCODE 0F7E: MOVD R/M32, MM: 02: MODRM + NO IMM
							; OPCODE 0F7F: MOVQ MM/MM64, MM: 02: MODRM + NO IMM
	DB 8 DUP(0DDH)					; OPCODES 0F80-0F8F: Jxx REL16/32: 0D NO MODRM + ADDRESS MODE + 4 BYTE IMM
	DB 8 DUP(22H)					; OPCODES 0F90-0F9F: SETxx: 02: MODRM + NO IMM
	DB 00H						; OPCODE 0FA0: PUSH FS: 00 NO MODRM + NO IMM
							; OPCODE 0FA1: POP FS: 00: NO MODRM + NO IMM
	DB 20H						; OPCODE 0FA2: CPUID: 00: NO MODRM + NO IMM
							; OPCODE 0FA3: BT R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 26H						; OPCODE 0FA4: SHLD R/M16/M32, R16/R32, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE 0FA5: SHLD R/M16/M32, R16/R32, CL: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FA6: NONE: 02: MODRM + NO IMM
							; OPCODE 0FA7: NONE: 02: MODRM + NO IMM
	DB 00H						; OPCODE 0FA8: PUSH GS: 00 NO MODRM + NO IMM
							; OPCODE 0FA9: POP GS: 00: NO MODRM + NO IMM
	DB 20H						; OPCODE 0FAA: RSM: 00: NO MODRM + NO IMM
							; OPCODE 0FAB: BTS R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 26H						; OPCODE 0FAC: SHRD R/M16/M32, R16/R32, IMM8: 06: MODRM + 1 BYTE IMM
							; OPCODE 0FAD: SHRD R/M16/M32, R16/R32, CL: 02: MODRM + NO IMM
	DB 20H						; OPCODE 0FAE: DIFFERENT COMMANDS: 00: NO MODRM + NO IMM
							; OPCODE 0FAF: IMUL R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FB0: CMPXCHG R/M8, AL: 02: MODRM + NO IMM
							; OPCODE 0FB1: CMPXCHG R/M16/M32, EAX: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FB2: LSS R16/R32, M16:M32: 02: MODRM + NO IMM
							; OPCODE 0FB3: BTR R/M16/M32, R16/R32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FB4: LFS R16/R32, M16:M32: 02: MODRM + NO IMM
							; OPCODE 0FB5: LGS R16/R32, M16:M32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FB6: MOVZX R16/R32, R/M8: 02: MODRM + NO IMM
							; OPCODE 0FB7: MOVZX R16/R32, R/M16: 02: MODRM + NO IMM
	DB 00H						; OPCODE 0FB8: NONE: 00 NO MODRM + NO IMM
							; OPCODE 0FB9: NONE: 00: NO MODRM + NO IMM
	DB 20H						; OPCODE 0FBA: BTx R/M16/M32, IMM8: 00: NO MODRM + NO IMM
							; SEEMS ERROR, SHOULD HAVE 1 BYTE IMM
							; OPCODE 0FBB: BTx R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FBC: BSF R16/R32, R/M16/M32: 02: MODRM + NO IMM
							; OPCODE 0FBD: BSR R16/R32, R/M16/M32: 02: MODRM + NO IMM
	DB 22H						; OPCODE 0FBE: MOVSX R16/R32, R/M8: 02: MODRM + NO IMM
							; OPCODE 0FBF: MOVSX R16/R32, R/M16: 02: MODRM + NO IMM
	DB 4 DUP(22H)					; OPCODES 0FC0-0FC7: VARIOUS SSE COMMANDS: 02: MODRM + NO IMM
	DB 4 DUP(00H)					; OPCODES 0FC8-0FCF: BSWAP R16/R32: 00: NO MODRM + NO IMM
	DB 23 DUP(22H)					; OPCODES 0FD0-0FFD: VARIOUS SSE COMMANDS: 02: MODRM + NO IMM
	DB 02H						; OPCODE 0FFE: PADD: 02: MODRM + NO IMM
							; OPCODE 0FFF: NONE: 00: NO MODRM + NO IMM

import_table:
	DB 0
	DD 0081F0B4h					; WINMM import addresses
	DB 'WINMM.dll', 0
	DB 'timeBeginPeriod', 0
	DB 'timeGetTime', 0

	DB 0
	DD 0081F034h					; KERNEL import addresses
	DB 'KERNEL32.dll', 0
	DB 'CreateThread', 0
	DB 'InitializeCriticalSection', 0
	DB 'CreateEventA',0
	DB 'GetProcAddress',0
	DB 'LoadLibraryA',0
	DB 'GetModuleHandleA',0
	DB 'GetProcessHeap',0
	DB 'HeapFree',0
	DB 'ExitProcess',0
	DB 'Sleep',0
	DB 'LeaveCriticalSection',0
	DB 'EnterCriticalSection',0
	DB 'SetEvent',0
	DB 'WaitForSingleObject',0
	DB 'HeapAlloc',0

	DB 0
	DD 0081F074h					; USER import addresses
	DB 'USER32.dll', 0
	DB 'CreateWindowExA',0
	DB 'RegisterClassA',0
	DB 'LoadCursorA',0
	DB 'LoadIconA',0
	DB 'GetDC',0
	DB 'TranslateMessage',0
	DB 'DispatchMessageA',0
	DB 'GetAsyncKeyState',0
	DB 'SetCursor',0
	DB 'ValidateRect',0
	DB 'GetCursorPos',0
	DB 'SetCursorPos',0
	DB 'PostQuitMessage',0
	DB 'PeekMessageA',0
	DB 'DefWindowProcA',0

	DB 0
	DD 0081F000h					; GDI import addresses
	DB 'GDI32.dll', 0
	DB 'CreateCompatibleDC',0
	DB 'GetDIBits',0
	DB 'ExtTextOutA',0
	DB 'GetTextExtentPoint32A',0
	DB 'CreateCompatibleBitmap',0
	DB 'SelectObject',0
	DB 'SetDIBits',0
	DB 'CreateFontA',0
	DB 'SetBkMode',0
	DB 'SetTextColor',0
	DB 'GetTextMetricsA',0
	DB 'DeleteObject',0

	DB 5 DUP(0)

; Comments below are assuming you use file 375395-byte file obtained during the
; stage 1 unpacking
segments_tables:

	DD 011A50h					; Offsets 00605H - 12054H: MAIN CODE STREAM

	DD 000297h					; Offsets 12055H - 122EBH: [EAX + DISP8] STREAM
	DD 0002D9h					; Offsets 122ECH - 125C4H: [ECX + DISP8] STREAM
	DD 0000FAh					; Offsets 125C5H - 126BEH: [EDX + DISP8] STREAM
	DD 000202h					; Offsets 126BFH - 128C0H: [EBX + DISP8] STREAM
	DD 000207h					; Offsets 128C1H - 12AC7H: [SIB + DISP8] STREAM
	DD 001F39h					; Offsets 12AC8H - 14A00H: [EBP + DISP8] STREAM
	DD 0003B3h					; Offsets 14A01H - 14DB3H: [ESI + DISP8] STREAM
	DD 0000F0h					; Offsets 14DB4H - 14EA3H: [EDI + DISP8] STREAM
	DD 000988h					; Offsets 14EA4H - 1582BH: DISP8 ADDRESS STREAM
	DD 000E19h					; Offsets 1582CH - 16644H: IMM8 STREAM
	DD 000366h					; Offsets 16645H - 169AAH: IMM16 STREAM
	DD 001534h					; Offsets 169ABH - 17EDEH: IMM32 STREAM
	DD 001E30h					; Offsets 17EDFH - 19D0EH: DISP32 REGISTER PLUS OFFSET 3 BYTES
	DD 000E1Ch					; Offsets 19D0FH - 1AB2AH: DISP32 ONLY OFFSET 3 BYTES
	DD 00022Bh					; Offsets 1AB2BH - 1AD55H: DISP32 ADDRESS 3 BYTES
	DD 000960h					; Offsets 1AD56H - 1B6B5H: CALL - FUNCTION NUMBER OR LOW DELTA
	DD 00053Ah					; Offsets 1B6B6H - 1BBEFH: DISP32 JMP LOW DELTA
	DD 000EC4h					; Offsets 1BBF0H - 1CAB3H: DISP32 OFFSET 4TH BYTE
	DD 0000B9h					; Offsets 1CAB4H - 1CB6CH: DISP32 ADDRESS 4TH BYTE
	DD 0006EAh					; Offsets 1CB6DH - 1D256H: DISP32 JMP OR CALL HIGH DELTA

; Here will be input data. It is offset 0605H in file obtained after stage 1
; unpacking
input_data:



virtual at 7D7C08h

data_for_part_2:

main_code_offset:	 	DD ?					; Start of Main Code Segment
eax_disp8_offset:		DD ?
ecx_disp8_offset:		DD ?
edx_disp8_offset:		DD ?
ebx_disp8_offset:		DD ?
sib_disp8_offset:		DD ?
ebp_disp8_offset:		DD ?
esi_disp8_offset:		DD ?
edi_disp8_offset:		DD ?
disp8_address:			DD ?
imm_8:				DD ?
imm_16:				DD ?
imm_32:				DD ?
disp32_reg_offset_3_byte:	DD ?
disp32_only_offset_3_byte:	DD ?
disp32_address_3_byte:		DD ?
call_func_number_or_low_delta:	DD ?
disp32_jump_low_delta:		DD ?
disp32_offset_fourth_byte:	DD ?
disp32_address_fourth_byte:	DD ?
disp32_jump_call_high_delta:	DD ?

starting_addr:				DD ?			; ADDRESS OF AN OUTPUT BUFFER (ACTUALLY 4 BYTE LESS)
last_jump:				DD ?			; LAST JMP DISPLACEMENT
next_function:				DD ?			; 0 - WE ARE WORKING WITH FUNCTION
								; 1 - NEXT BYTE CAN BE NEW FUNCTION ADDRESS
function_table_position:		DD ?			; NUMBER OF FUNCTION IN FUNCTION TABLE
								; (SEE function_addresses LABEL)

function_addresses:		DD 256 DUP(?)			; OFFSETS OF FUNCTIONS (CIRCLE BUFFER)

end virtual