const std = @import("std");

// ─── Protocol version constants ────────────────────────────────────

pub const PROTOCOL_VERSION_3_0: i32 = 196608; // 3.0 in protocol format (3 << 16 | 0)
pub const SSL_REQUEST_CODE: i32 = 80877103;
pub const CANCEL_REQUEST_CODE: i32 = 80877102;

// ─── Message type constants ────────────────────────────────────────

pub const MessageType = struct {
    // Frontend (client -> server)
    pub const query = 'Q';
    pub const parse = 'P';
    pub const bind = 'B';
    pub const describe = 'D';
    pub const execute = 'E';
    pub const sync = 'S';
    pub const terminate = 'X';
    pub const password_message = 'p';
    pub const copy_data = 'd';
    pub const copy_done = 'c';
    pub const copy_fail = 'f';
    pub const function_call = 'F';
    pub const flush = 'H';
    pub const close = 'C';

    // Backend (server -> client)
    pub const authentication = 'R';
    pub const backend_key_data = 'K';
    pub const bind_complete = '2';
    pub const command_complete = 'C';
    pub const data_row = 'D';
    pub const empty_query_response = 'I';
    pub const error_response = 'E';
    pub const function_call_response = 'V';
    pub const no_data = 'n';
    pub const notice_response = 'N';
    pub const notification_response = 'A';
    pub const parameter_description = 't';
    pub const parameter_status = 'S';
    pub const parse_complete = '1';
    pub const portal_suspended = 's';
    pub const ready_for_query = 'Z';
    pub const row_description = 'T';
    pub const copy_in_response = 'G';
    pub const copy_out_response = 'H';
    pub const copy_both_response = 'W';
};

// ─── Authentication method constants ───────────────────────────────

pub const AuthMethod = struct {
    pub const ok = 0;
    pub const kerberos_v4 = 1;
    pub const kerberos_v5 = 2;
    pub const cleartext_password = 3;
    pub const crypt_password = 4;
    pub const md5_password = 5;
    pub const scm_credential = 6;
    pub const gss = 7;
    pub const gss_continue = 8;
    pub const sspi = 9;
    pub const sasl = 10;
    pub const sasl_continue = 11;
    pub const sasl_final = 12;
};

// ─── SASL mechanism constants ──────────────────────────────────────

pub const SaslMechanism = struct {
    pub const scram_sha_256 = "SCRAM-SHA-256";
    pub const scram_sha_256_plus = "SCRAM-SHA-256-PLUS";
};

// ─── SCRAM authentication states ───────────────────────────────────

pub const ScramState = enum {
    initial,
    first_sent,
    ended,
    errored,
};

// ─── Transaction status constants ──────────────────────────────────

pub const TransactionStatus = struct {
    pub const idle = 'I';
    pub const in_transaction = 'T';
    pub const in_failed_transaction = 'E';
};

// ─── Data type OID constants ───────────────────────────────────────

pub const DataType = struct {
    pub const BOOL: i32 = 16;
    pub const BYTEA: i32 = 17;
    pub const CHAR: i32 = 18;
    pub const NAME: i32 = 19;
    pub const INT8: i32 = 20;
    pub const INT2: i32 = 21;
    pub const INT2VECTOR: i32 = 22;
    pub const INT4: i32 = 23;
    pub const REGPROC: i32 = 24;
    pub const TEXT: i32 = 25;
    pub const OID: i32 = 26;
    pub const TID: i32 = 27;
    pub const XID: i32 = 28;
    pub const CID: i32 = 29;
    pub const OIDVECTOR: i32 = 30;
    pub const JSON: i32 = 114;
    pub const XML: i32 = 142;
    pub const PGNODETREE: i32 = 194;
    pub const POINT: i32 = 600;
    pub const LSEG: i32 = 601;
    pub const PATH: i32 = 602;
    pub const BOX: i32 = 603;
    pub const POLYGON: i32 = 604;
    pub const LINE: i32 = 628;
    pub const FLOAT4: i32 = 700;
    pub const FLOAT8: i32 = 701;
    pub const ABSTIME: i32 = 702;
    pub const RELTIME: i32 = 703;
    pub const TINTERVAL: i32 = 704;
    pub const UNKNOWN: i32 = 705;
    pub const CIRCLE: i32 = 718;
    pub const CASH: i32 = 790;
    pub const MACADDR: i32 = 829;
    pub const INET: i32 = 869;
    pub const CIDR: i32 = 650;
    pub const MACADDR8: i32 = 774;
    pub const ACLITEM: i32 = 1033;
    pub const BPCHAR: i32 = 1042;
    pub const VARCHAR: i32 = 1043;
    pub const DATE: i32 = 1082;
    pub const TIME: i32 = 1083;
    pub const TIMESTAMP: i32 = 1114;
    pub const TIMESTAMPTZ: i32 = 1184;
    pub const INTERVAL: i32 = 1186;
    pub const TIMETZ: i32 = 1266;
    pub const BIT: i32 = 1560;
    pub const VARBIT: i32 = 1562;
    pub const NUMERIC: i32 = 1700;
    pub const REFCURSOR: i32 = 1790;
    pub const REGPROCEDURE: i32 = 2202;
    pub const REGOPER: i32 = 2203;
    pub const REGOPERATOR: i32 = 2204;
    pub const REGCLASS: i32 = 2205;
    pub const REGTYPE: i32 = 2206;
    pub const UUID: i32 = 2950;
    pub const TXID_SNAPSHOT: i32 = 2970;
    pub const PG_LSN: i32 = 3220;
    pub const TSVECTOR: i32 = 3614;
    pub const TSQUERY: i32 = 3615;
    pub const GTSVECTOR: i32 = 3642;
    pub const REGCONFIG: i32 = 3734;
    pub const REGDICTIONARY: i32 = 3769;
    pub const JSONB: i32 = 3802;
    pub const INT4RANGE: i32 = 3904;
    pub const NUMRANGE: i32 = 3906;
    pub const TSRANGE: i32 = 3908;
    pub const TSTZRANGE: i32 = 3910;
    pub const DATERANGE: i32 = 3912;
    pub const INT8RANGE: i32 = 3926;

    // Array types
    pub const BOOL_ARRAY: i32 = 1000;
    pub const BYTEA_ARRAY: i32 = 1001;
    pub const CHAR_ARRAY: i32 = 1002;
    pub const NAME_ARRAY: i32 = 1003;
    pub const INT2_ARRAY: i32 = 1005;
    pub const INT2VECTOR_ARRAY: i32 = 1006;
    pub const INT4_ARRAY: i32 = 1007;
    pub const REGPROC_ARRAY: i32 = 1008;
    pub const TEXT_ARRAY: i32 = 1009;
    pub const OID_ARRAY: i32 = 1028;
    pub const TID_ARRAY: i32 = 1010;
    pub const XID_ARRAY: i32 = 1011;
    pub const CID_ARRAY: i32 = 1012;
    pub const OIDVECTOR_ARRAY: i32 = 1013;
    pub const BPCHAR_ARRAY: i32 = 1014;
    pub const VARCHAR_ARRAY: i32 = 1015;
    pub const INT8_ARRAY: i32 = 1016;
    pub const POINT_ARRAY: i32 = 1017;
    pub const LSEG_ARRAY: i32 = 1018;
    pub const PATH_ARRAY: i32 = 1019;
    pub const BOX_ARRAY: i32 = 1020;
    pub const FLOAT4_ARRAY: i32 = 1021;
    pub const FLOAT8_ARRAY: i32 = 1022;
    pub const ABSTIME_ARRAY: i32 = 1023;
    pub const RELTIME_ARRAY: i32 = 1024;
    pub const TINTERVAL_ARRAY: i32 = 1025;
    pub const POLYGON_ARRAY: i32 = 1027;
    pub const ACLITEM_ARRAY: i32 = 1034;
    pub const MACADDR_ARRAY: i32 = 1040;
    pub const INET_ARRAY: i32 = 1041;
    pub const CIDR_ARRAY: i32 = 651;
    pub const TIMESTAMP_ARRAY: i32 = 1115;
    pub const DATE_ARRAY: i32 = 1182;
    pub const TIME_ARRAY: i32 = 1183;
    pub const TIMESTAMPTZ_ARRAY: i32 = 1185;
    pub const INTERVAL_ARRAY: i32 = 1187;
    pub const NUMERIC_ARRAY: i32 = 1231;
    pub const TIMETZ_ARRAY: i32 = 1270;
    pub const BIT_ARRAY: i32 = 1561;
    pub const VARBIT_ARRAY: i32 = 1563;
    pub const UUID_ARRAY: i32 = 2951;
    pub const TXID_SNAPSHOT_ARRAY: i32 = 2949;
    pub const JSON_ARRAY: i32 = 199;
    pub const JSONB_ARRAY: i32 = 3807;
};

// ─── Format codes ──────────────────────────────────────────────────

pub const FormatCode = struct {
    pub const text = 0;
    pub const binary = 1;
};

// ─── Error severity levels ─────────────────────────────────────────

pub const ErrorSeverity = struct {
    pub const @"error" = "ERROR";
    pub const fatal = "FATAL";
    pub const panic = "PANIC";
    pub const warning = "WARNING";
    pub const notice = "NOTICE";
    pub const debug = "DEBUG";
    pub const info = "INFO";
    pub const log = "LOG";
};

// ─── Common error codes (SQLSTATE) ─────────────────────────────────

pub const ErrorCode = struct {
    // Class 00 — Successful Completion
    pub const successful_completion = "00000";

    // Class 01 — Warning
    pub const warning = "01000";
    pub const dynamic_result_sets_returned = "0100C";
    pub const implicit_zero_bit_padding = "01008";
    pub const null_value_eliminated_in_set_function = "01003";
    pub const privilege_not_granted = "01007";
    pub const privilege_not_revoked = "01006";
    pub const string_data_right_truncation_warning = "01004";
    pub const deprecated_feature = "01P01";

    // Class 02 — No Data
    pub const no_data = "02000";
    pub const no_additional_dynamic_result_sets_returned = "02001";

    // Class 03 — SQL Statement Not Yet Complete
    pub const sql_statement_not_yet_complete = "03000";

    // Class 08 — Connection Exception
    pub const connection_exception = "08000";
    pub const connection_does_not_exist = "08003";
    pub const connection_failure = "08006";
    pub const sqlclient_unable_to_establish_sqlconnection = "08001";
    pub const sqlserver_rejected_establishment_of_sqlconnection = "08004";
    pub const transaction_resolution_unknown = "08007";
    pub const protocol_violation = "08P01";

    // Class 09 — Triggered Action Exception
    pub const triggered_action_exception = "09000";

    // Class 0A — Feature Not Supported
    pub const feature_not_supported = "0A000";

    // Class 0B — Invalid Transaction Initiation
    pub const invalid_transaction_initiation = "0B000";

    // Class 0F — Locator Exception
    pub const locator_exception = "0F000";
    pub const invalid_locator_specification = "0F001";

    // Class 0L — Invalid Grantor
    pub const invalid_grantor = "0L000";
    pub const invalid_grant_operation = "0LP01";

    // Class 0P — Invalid Role Specification
    pub const invalid_role_specification = "0P000";

    // Class 20 — Case Not Found
    pub const case_not_found = "20000";

    // Class 21 — Cardinality Violation
    pub const cardinality_violation = "21000";

    // Class 22 — Data Exception
    pub const data_exception = "22000";
    pub const array_subscript_error = "2202E";
    pub const character_not_in_repertoire = "22021";
    pub const datetime_field_overflow = "22008";
    pub const division_by_zero = "22012";
    pub const error_in_assignment = "22005";
    pub const escape_character_conflict = "2200B";
    pub const indicator_overflow = "22022";
    pub const interval_field_overflow = "22015";
    pub const invalid_argument_for_logarithm = "2201E";
    pub const invalid_argument_for_ntile_function = "22014";
    pub const invalid_argument_for_nth_value_function = "22016";
    pub const invalid_argument_for_power_function = "2201F";
    pub const invalid_argument_for_width_bucket_function = "2201G";
    pub const invalid_character_value_for_cast = "22018";
    pub const invalid_datetime_format = "22007";
    pub const invalid_escape_character = "22019";
    pub const invalid_escape_octet = "2200D";
    pub const invalid_escape_sequence = "22025";
    pub const nonstandard_use_of_escape_character = "22P06";
    pub const invalid_indicator_parameter_value = "22010";
    pub const invalid_parameter_value = "22023";
    pub const invalid_regular_expression = "2201B";
    pub const invalid_row_count_in_limit_clause = "2201W";
    pub const invalid_row_count_in_result_offset_clause = "2201X";
    pub const invalid_time_zone_displacement_value = "22009";
    pub const invalid_use_of_escape_character = "2200C";
    pub const most_specific_type_mismatch = "2200G";
    pub const null_value_not_allowed = "22004";
    pub const null_value_no_indicator_parameter = "22002";
    pub const numeric_value_out_of_range = "22003";
    pub const string_data_length_mismatch = "22026";
    pub const string_data_right_truncation = "22001";
    pub const substring_error = "22011";
    pub const trim_error = "22027";
    pub const unterminated_c_string = "22024";
    pub const zero_length_character_string = "2200F";
    pub const floating_point_exception = "22P01";
    pub const invalid_text_representation = "22P02";
    pub const invalid_binary_representation = "22P03";
    pub const bad_copy_file_format = "22P04";
    pub const untranslatable_character = "22P05";
    pub const not_an_xml_document = "2200L";
    pub const invalid_xml_document = "2200M";
    pub const invalid_xml_content = "2200N";
    pub const invalid_xml_comment = "2200S";
    pub const invalid_xml_processing_instruction = "2200T";

    // Class 23 — Integrity Constraint Violation
    pub const integrity_constraint_violation = "23000";
    pub const restrict_violation = "23001";
    pub const not_null_violation = "23502";
    pub const foreign_key_violation = "23503";
    pub const unique_violation = "23505";
    pub const check_violation = "23514";
    pub const exclusion_violation = "23P01";

    // Class 24 — Invalid Cursor State
    pub const invalid_cursor_state = "24000";

    // Class 25 — Invalid Transaction State
    pub const invalid_transaction_state = "25000";
    pub const active_sql_transaction = "25001";
    pub const branch_transaction_already_active = "25002";
    pub const held_cursor_requires_same_isolation_level = "25008";
    pub const inappropriate_access_mode_for_branch_transaction = "25003";
    pub const inappropriate_isolation_level_for_branch_transaction = "25004";
    pub const no_active_sql_transaction_for_branch_transaction = "25005";
    pub const read_only_sql_transaction = "25006";
    pub const schema_and_data_statement_mixing_not_supported = "25007";
    pub const no_active_sql_transaction = "25P01";
    pub const in_failed_sql_transaction = "25P02";

    // Class 26 — Invalid SQL Statement Name
    pub const invalid_sql_statement_name = "26000";

    // Class 27 — Triggered Data Change Violation
    pub const triggered_data_change_violation = "27000";

    // Class 28 — Invalid Authorization Specification
    pub const invalid_authorization_specification = "28000";
    pub const invalid_password = "28P01";

    // Class 2B — Dependent Privilege Descriptors Still Exist
    pub const dependent_privilege_descriptors_still_exist = "2B000";
    pub const dependent_objects_still_exist = "2BP01";

    // Class 2D — Invalid Transaction Termination
    pub const invalid_transaction_termination = "2D000";

    // Class 2F — SQL Routine Exception
    pub const sql_routine_exception = "2F000";
    pub const function_executed_no_return_statement = "2F005";
    pub const modifying_sql_data_not_permitted = "2F002";
    pub const prohibited_sql_statement_attempted = "2F003";
    pub const reading_sql_data_not_permitted = "2F004";

    // Class 34 — Invalid Cursor Name
    pub const invalid_cursor_name = "34000";

    // Class 38 — External Routine Exception
    pub const external_routine_exception = "38000";
    pub const containing_sql_not_permitted = "38001";
    pub const modifying_sql_data_not_permitted_external = "38002";
    pub const prohibited_sql_statement_attempted_external = "38003";
    pub const reading_sql_data_not_permitted_external = "38004";

    // Class 39 — External Routine Invocation Exception
    pub const external_routine_invocation_exception = "39000";
    pub const invalid_sqlstate_returned = "39001";
    pub const null_value_not_allowed_external = "39004";
    pub const trigger_protocol_violated = "39P01";
    pub const srf_protocol_violated = "39P02";

    // Class 3B — Savepoint Exception
    pub const savepoint_exception = "3B000";
    pub const invalid_savepoint_specification = "3B001";

    // Class 3D — Invalid Catalog Name
    pub const invalid_catalog_name = "3D000";

    // Class 3F — Invalid Schema Name
    pub const invalid_schema_name = "3F000";

    // Class 40 — Transaction Rollback
    pub const transaction_rollback = "40000";
    pub const transaction_integrity_constraint_violation = "40002";
    pub const serialization_failure = "40001";
    pub const statement_completion_unknown = "40003";
    pub const deadlock_detected = "40P01";

    // Class 42 — Syntax Error or Access Rule Violation
    pub const syntax_error_or_access_rule_violation = "42000";
    pub const syntax_error = "42601";
    pub const insufficient_privilege = "42501";
    pub const cannot_coerce = "42846";
    pub const grouping_error = "42803";
    pub const windowing_error = "42P20";
    pub const invalid_recursion = "42P19";
    pub const invalid_foreign_key = "42830";
    pub const invalid_name = "42602";
    pub const name_too_long = "42622";
    pub const reserved_name = "42939";
    pub const datatype_mismatch = "42804";
    pub const indeterminate_datatype = "42P18";
    pub const collation_mismatch = "42P21";
    pub const indeterminate_collation = "42P22";
    pub const wrong_object_type = "42809";
    pub const undefined_column = "42703";
    pub const undefined_function = "42883";
    pub const undefined_table = "42P01";
    pub const undefined_parameter = "42P02";
    pub const undefined_object = "42704";
    pub const duplicate_column = "42701";
    pub const duplicate_cursor = "42P03";
    pub const duplicate_database = "42P04";
    pub const duplicate_function = "42723";
    pub const duplicate_prepared_statement = "42P05";
    pub const duplicate_schema = "42P06";
    pub const duplicate_table = "42P07";
    pub const duplicate_alias = "42712";
    pub const duplicate_object = "42710";
    pub const ambiguous_column = "42702";
    pub const ambiguous_function = "42725";
    pub const ambiguous_parameter = "42P08";
    pub const ambiguous_alias = "42P09";
    pub const invalid_column_reference = "42P10";
    pub const invalid_column_definition = "42611";
    pub const invalid_cursor_definition = "42P11";
    pub const invalid_database_definition = "42P12";
    pub const invalid_function_definition = "42P13";
    pub const invalid_prepared_statement_definition = "42P14";
    pub const invalid_schema_definition = "42P15";
    pub const invalid_table_definition = "42P16";
    pub const invalid_object_definition = "42P17";

    // Class 44 — WITH CHECK OPTION Violation
    pub const with_check_option_violation = "44000";

    // Class 53 — Insufficient Resources
    pub const insufficient_resources = "53000";
    pub const disk_full = "53100";
    pub const out_of_memory = "53200";
    pub const too_many_connections = "53300";
    pub const configuration_limit_exceeded = "53400";

    // Class 54 — Program Limit Exceeded
    pub const program_limit_exceeded = "54000";
    pub const statement_too_complex = "54001";
    pub const too_many_columns = "54011";
    pub const too_many_arguments = "54023";

    // Class 55 — Object Not In Prerequisite State
    pub const object_not_in_prerequisite_state = "55000";
    pub const object_in_use = "55006";
    pub const cant_change_runtime_param = "55P02";
    pub const lock_not_available = "55P03";

    // Class 57 — Operator Intervention
    pub const operator_intervention = "57000";
    pub const query_canceled = "57014";
    pub const admin_shutdown = "57P01";
    pub const crash_shutdown = "57P02";
    pub const cannot_connect_now = "57P03";
    pub const database_dropped = "57P04";

    // Class 58 — System Error
    pub const system_error = "58000";
    pub const io_error = "58030";
    pub const undefined_file = "58P01";
    pub const duplicate_file = "58P02";

    // Class F0 — Configuration File Error
    pub const config_file_error = "F0000";
    pub const lock_file_exists = "F0001";

    // Class HV — Foreign Data Wrapper Error
    pub const fdw_error = "HV000";
    pub const fdw_column_name_not_found = "HV005";
    pub const fdw_dynamic_parameter_value_needed = "HV002";
    pub const fdw_function_sequence_error = "HV010";
    pub const fdw_inconsistent_descriptor_information = "HV021";
    pub const fdw_invalid_attribute_value = "HV024";
    pub const fdw_invalid_column_name = "HV007";
    pub const fdw_invalid_column_number = "HV008";
    pub const fdw_invalid_data_type = "HV004";
    pub const fdw_invalid_data_type_descriptors = "HV006";
    pub const fdw_invalid_descriptor_field_identifier = "HV091";
    pub const fdw_invalid_handle = "HV00B";
    pub const fdw_invalid_option_index = "HV00C";
    pub const fdw_invalid_option_name = "HV00D";
    pub const fdw_invalid_string_length_or_buffer_length = "HV090";
    pub const fdw_invalid_string_format = "HV00A";
    pub const fdw_invalid_use_of_null_pointer = "HV009";
    pub const fdw_too_many_handles = "HV014";
    pub const fdw_out_of_memory = "HV001";
    pub const fdw_no_schemas = "HV00P";
    pub const fdw_option_name_not_found = "HV00J";
    pub const fdw_reply_handle = "HV00K";
    pub const fdw_schema_not_found = "HV00Q";
    pub const fdw_table_not_found = "HV00R";
    pub const fdw_unable_to_create_execution = "HV00L";
    pub const fdw_unable_to_create_reply = "HV00M";
    pub const fdw_unable_to_establish_connection = "HV00N";

    // Class P0 — PL/pgSQL Error
    pub const plpgsql_error = "P0000";
    pub const raise_exception = "P0001";
    pub const no_data_found = "P0002";
    pub const too_many_rows = "P0003";

    // Class XX — Internal Error
    pub const internal_error = "XX000";
    pub const data_corrupted = "XX001";
    pub const index_corrupted = "XX002";

    // SCRAM Authentication Error Codes
    pub const scram_invalid_proof = "28000";
    pub const scram_invalid_authorization_message = "28000";
    pub const scram_channel_binding_not_supported = "0A000";
    pub const scram_channel_binding_required = "28000";
    pub const scram_unknown_attribute = "08P01";
    pub const scram_invalid_nonce = "08P01";
    pub const scram_iteration_count_mismatch = "08P01";
};

// ─── Standardized error messages ───────────────────────────────────

pub const ErrorMessage = struct {
    // Query parsing errors
    pub const empty_query = "empty query string";
    pub const unterminated_string = "unterminated quoted string";
    pub const unterminated_identifier = "unterminated quoted identifier";

    // Protocol errors
    pub const invalid_message_format = "invalid message format";
    pub const invalid_parse_message = "invalid Parse message format";
    pub const invalid_bind_message = "invalid Bind message format";
    pub const invalid_describe_message = "invalid Describe message format";
    pub const invalid_execute_message = "invalid Execute message format";
    pub const unknown_message_type = "unknown message type";
    pub const protocol_error = "protocol error";
    pub const message_processing_error = "message processing error";
    pub const malformed_cancel_request = "malformed cancel request received";

    // Array errors
    pub const invalid_array_format = "Invalid array format";
    pub const missing_outer_braces = "Invalid array format: missing outer braces";
    pub const mismatched_braces = "Invalid array format: mismatched braces";
    pub const invalid_array_element = "invalid array element";
    pub const array_dimension_mismatch = "multidimensional arrays must have array expressions with matching dimensions";

    // Feature support errors
    pub const function_call_not_supported = "function call protocol not supported";
    pub const copy_not_supported = "COPY protocol not supported in this server";
    pub const feature_not_implemented = "feature is not implemented";

    // Object existence errors
    pub const portal_does_not_exist = "portal does not exist";
    pub const prepared_statement_does_not_exist = "prepared statement does not exist";
    pub const cursor_does_not_exist = "cursor does not exist";

    // Copy protocol errors
    pub const copy_failed = "COPY failed";
    pub const copy_in_progress = "COPY in progress";

    // Data type errors
    pub const invalid_input_syntax = "invalid input syntax";
    pub const invalid_text_representation = "invalid input syntax for type";
    pub const type_mismatch = "type mismatch";
    pub const cannot_cast = "cannot cast type";

    // Transaction errors
    pub const not_in_transaction = "there is no transaction in progress";
    pub const already_in_transaction = "there is already a transaction in progress";
    pub const transaction_aborted = "current transaction is aborted, commands ignored until end of transaction block";
    pub const unknown_transaction_command = "unknown transaction command";

    // Query errors
    pub const invalid_set_syntax = "invalid SET command syntax";

    // Resource errors
    pub const too_many_connections = "sorry, too many clients already";
    pub const out_of_memory = "out of memory";
    pub const query_too_long = "query string is too long";

    // MD5 Authentication errors
    pub const md5_auth_failed = "password authentication failed";

    // SCRAM Authentication errors
    pub const scram_invalid_proof = "authentication failed";
    pub const scram_invalid_authorization_message = "invalid SCRAM authorization message";
    pub const scram_channel_binding_not_supported = "channel binding not supported";
    pub const scram_channel_binding_required = "channel binding required but not provided";
    pub const scram_unknown_attribute = "unknown SCRAM attribute";
    pub const scram_invalid_nonce = "invalid nonce in SCRAM exchange";
    pub const scram_iteration_count_mismatch = "iteration count mismatch in SCRAM";
    pub const scram_mechanism_not_supported = "SCRAM mechanism not supported";

    // General errors
    pub const internal_error = "internal error";
    pub const unexpected_error = "unexpected error occurred";
};

// ─── Default server parameters ─────────────────────────────────────

pub const DefaultServerParameters = struct {
    pub const server_version = "13.0 (Mock)";
    pub const server_encoding = "UTF8";
    pub const client_encoding = "UTF8";
    pub const application_name = "";
    pub const is_superuser = "off";
    pub const session_authorization = "postgres";
    pub const date_style = "ISO, MDY";
    pub const interval_style = "postgres";
    pub const time_zone = "UTC";
    pub const integer_datetimes = "on";
    pub const standard_conforming_strings = "on";
};

// ─── Pre-built payloads ────────────────────────────────────────────

pub const AuthOkPayload = [_]u8{ 0, 0, 0, 0 };
pub const AuthOkLength = [_]u8{ 0, 0, 0, 8 };
pub const ReadyForQueryLength = [_]u8{ 0, 0, 0, 5 };

// ─── Column descriptor ─────────────────────────────────────────────

pub const ColumnDesc = struct {
    name: []const u8,
    type_oid: i32,
    type_len: i16,
};

// ─── Message ───────────────────────────────────────────────────────

pub const Message = struct {
    type: u8,
    payload: []u8,
};

pub const StartupMessage = struct {
    version: i32,
    params: []const u8,
};
