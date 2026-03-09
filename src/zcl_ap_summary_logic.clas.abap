CLASS zcl_ap_summary_logic DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_AP_SUMMARY_LOGIC IMPLEMENTATION.


  METHOD if_rap_query_provider~select.

    TYPES: BEGIN OF lty_range_option,
             sign   TYPE c LENGTH 1,
             option TYPE c LENGTH 2,
             low    TYPE string,
             high   TYPE string,
           END OF lty_range_option.

    DATA: lt_result        TYPE TABLE OF zc_accpay_summary,
          lt_result1       TYPE TABLE OF zc_accpay_summary,
          lv_start_date    TYPE zc_accpay_summary-p_start_date,
          lv_end_date      TYPE zc_accpay_summary-p_end_date,
          lt_range         TYPE TABLE OF lty_range_option,
          lv_compcode_prov TYPE abap_bool,
          lv_bpgroup_prov  TYPE abap_bool,
          lv_account_prov  TYPE abap_bool,
          lv_partner_prov  TYPE abap_bool,
          ev_balance       TYPE wrbtr,
          lv_currency_prov TYPE abap_bool,
          lr_companycode   TYPE RANGE OF i_journalentryitem-companycode,
          lr_bpgroup       TYPE RANGE OF i_businesspartner-businesspartnergrouping,
          lr_account       TYPE RANGE OF i_journalentryitem-glaccount,
          lr_partner       TYPE RANGE OF i_journalentryitem-supplier,
          lv_currency      TYPE zc_accpay_summary-companycodecurrency,
          lr_currency      TYPE RANGE OF i_journalentryitem-transactioncurrency.
    CLEAR: lt_result.

    " 1. Extract filter parameters
    CHECK io_request IS BOUND.
    TRY.
        DATA(lo_filter) = io_request->get_filter( ).
        CHECK lo_filter IS BOUND.
        DATA(lt_filter_ranges) = lo_filter->get_as_ranges( ).

        " Mandatory date filters
        READ TABLE lt_filter_ranges INTO DATA(ls_start_date) WITH KEY name = 'P_START_DATE'.
        IF sy-subrc = 0 AND ls_start_date-range IS NOT INITIAL.
          lv_start_date = ls_start_date-range[ 1 ]-low.
        ENDIF.

        READ TABLE lt_filter_ranges INTO DATA(ls_end_date) WITH KEY name = 'P_END_DATE'.
        IF sy-subrc = 0 AND ls_end_date-range IS NOT INITIAL.
          lv_end_date = ls_end_date-range[ 1 ]-low.
        ENDIF.
        "Mandatory currency filter
*        READ TABLE lt_filter_ranges INTO DATA(ls_currency) WITH KEY name = 'RHCUR'.
*        IF sy-subrc = 0 AND ls_currency-range IS NOT INITIAL.
*          lv_currency = ls_currency-range[ 1 ]-low.
*        ENDIF.

        " Optional filters with ALPHA conversion

        TRY.
            DATA(lr_currency_raw) = lt_filter_ranges[ name = 'RHCUR' ]-range.
            LOOP AT lr_currency_raw ASSIGNING FIELD-SYMBOL(<fs_currency>).
              IF <fs_currency>-low IS NOT INITIAL.
                <fs_currency>-low = |{ <fs_currency>-low ALPHA = IN WIDTH = 5 }|.
              ENDIF.
              IF <fs_currency>-high IS NOT INITIAL.
                <fs_currency>-high = |{ <fs_currency>-high ALPHA = IN WIDTH = 5 }|.
              ENDIF.
            ENDLOOP.
            MOVE-CORRESPONDING lr_currency_raw TO lr_currency.
            lv_currency_prov = abap_true.
          CATCH cx_sy_itab_line_not_found.
            CLEAR lr_currency.
        ENDTRY.


        TRY.
            DATA(lr_compcode_raw) = lt_filter_ranges[ name = 'RBUKRS' ]-range.
            LOOP AT lr_compcode_raw ASSIGNING FIELD-SYMBOL(<fs_compcode>).
              IF <fs_compcode>-low IS NOT INITIAL.
                <fs_compcode>-low = |{ <fs_compcode>-low ALPHA = IN WIDTH = 4 }|.
              ENDIF.
              IF <fs_compcode>-high IS NOT INITIAL.
                <fs_compcode>-high = |{ <fs_compcode>-high ALPHA = IN WIDTH = 4 }|.
              ENDIF.
            ENDLOOP.
            MOVE-CORRESPONDING lr_compcode_raw TO lr_companycode.
            lv_compcode_prov = abap_true.
          CATCH cx_sy_itab_line_not_found.
            CLEAR lr_companycode.
        ENDTRY.

        TRY.
            DATA(lr_partner_raw) = lt_filter_ranges[ name = 'BP' ]-range.
            LOOP AT lr_partner_raw ASSIGNING FIELD-SYMBOL(<fs_partner>).
              IF <fs_partner>-low IS NOT INITIAL.
                <fs_partner>-low = |{ <fs_partner>-low ALPHA = IN WIDTH = 10 }|.
              ENDIF.
              IF <fs_partner>-high IS NOT INITIAL.
                <fs_partner>-high = |{ <fs_partner>-high ALPHA = IN WIDTH = 10 }|.
              ENDIF.
            ENDLOOP.
            MOVE-CORRESPONDING lr_partner_raw TO lr_partner.
            lv_partner_prov = abap_true.
          CATCH cx_sy_itab_line_not_found.
            CLEAR lr_partner.
        ENDTRY.

*        TRY.
*            DATA(lr_account_raw) = lt_filter_ranges[ name = 'ACCOUNTNUMBER' ]-range.
*            LOOP AT lr_account_raw ASSIGNING FIELD-SYMBOL(<fs_account>).
*              IF <fs_account>-low IS NOT INITIAL.
*                <fs_account>-low = |{ <fs_account>-low ALPHA = IN WIDTH = 10 }|.
*              ENDIF.
*              IF <fs_account>-high IS NOT INITIAL.
*                <fs_account>-high = |{ <fs_account>-high ALPHA = IN WIDTH = 10 }|.
*              ENDIF.
*            ENDLOOP.
*            MOVE-CORRESPONDING lr_account_raw TO lr_account.
*            lv_account_prov = abap_true.
*          CATCH cx_sy_itab_line_not_found.
*            CLEAR lr_account.
*        ENDTRY.

        TRY.
            DATA(lr_account_raw) = lt_filter_ranges[ name = 'ACCOUNTNUMBER' ]-range.
            CLEAR lr_account.

            LOOP AT lr_account_raw INTO DATA(ls_account_filter).
              " Handle different search patterns
              CASE ls_account_filter-option.
                WHEN 'CP'. " Contains Pattern
                  IF ls_account_filter-low CS '*'.
                    " For wildcard searches like 131*
                    " Create multiple patterns to catch different formats

                    " Pattern 1: Original pattern (for cases like NU131302)
                    APPEND VALUE #(
                      sign = ls_account_filter-sign
                      option = 'CP'
                      low = ls_account_filter-low
                      high = ls_account_filter-high
                    ) TO lr_account.

                    " Pattern 2: *value* pattern (contains anywhere)
                    DATA(lv_base_value) = ls_account_filter-low.
                    REPLACE ALL OCCURRENCES OF '*' IN lv_base_value WITH ''.
                    IF lv_base_value IS NOT INITIAL.
                      APPEND VALUE #(
                        sign = ls_account_filter-sign
                        option = 'CP'
                        low = |*{ lv_base_value }*|
                        high = ls_account_filter-high
                      ) TO lr_account.
                    ENDIF.
                  ELSE.
                    " Non-wildcard CP patterns
                    APPEND VALUE #(
                      sign = ls_account_filter-sign
                      option = ls_account_filter-option
                      low = ls_account_filter-low
                      high = ls_account_filter-high
                    ) TO lr_account.
                  ENDIF.

                WHEN 'EQ'. " Exact match
                  " For exact matches, try both original and ALPHA padded
                  APPEND VALUE #(
                    sign = ls_account_filter-sign
                    option = 'EQ'
                    low = ls_account_filter-low
                    high = ls_account_filter-high
                  ) TO lr_account.

                  " Also add ALPHA padded version
                  APPEND VALUE #(
                    sign = ls_account_filter-sign
                    option = 'EQ'
                    low = |{ ls_account_filter-low ALPHA = IN WIDTH = 10 }|
                    high = ls_account_filter-high
                  ) TO lr_account.

                WHEN OTHERS.
                  " Keep other options as-is
                  APPEND VALUE #(
                    sign = ls_account_filter-sign
                    option = ls_account_filter-option
                    low = ls_account_filter-low
                    high = ls_account_filter-high
                  ) TO lr_account.
              ENDCASE.
            ENDLOOP.

            lv_account_prov = abap_true.
          CATCH cx_sy_itab_line_not_found.
            CLEAR lr_account.
        ENDTRY.


        TRY.
            DATA(lr_bpgroup_raw) = lt_filter_ranges[ name = 'BP_GR' ]-range.
            LOOP AT lr_bpgroup_raw ASSIGNING FIELD-SYMBOL(<fs_bpgr>).
              IF <fs_bpgr>-low IS NOT INITIAL.
                <fs_bpgr>-low = |{ <fs_bpgr>-low ALPHA = IN WIDTH = 4 }|.
              ENDIF.
              IF <fs_bpgr>-high IS NOT INITIAL.
                <fs_bpgr>-high = |{ <fs_bpgr>-high ALPHA = IN WIDTH = 4 }|.
              ENDIF.
            ENDLOOP.
            MOVE-CORRESPONDING lr_bpgroup_raw TO lr_bpgroup.
            lv_bpgroup_prov = abap_true.
          CATCH cx_sy_itab_line_not_found.
            CLEAR lr_bpgroup.
        ENDTRY.

      CATCH cx_rap_query_filter_no_range INTO DATA(lx_filter_error).
        " Log error or raise message for debugging
        RETURN.
    ENDTRY.

    " get company name and address
    DATA: lw_company          TYPE bukrs,
          ls_companycode_info TYPE zst_companycode_info.
    lw_company = lr_companycode[ 1 ]-low.
    CALL METHOD zcl_jp_common_core=>get_companycode_details
      EXPORTING
        i_companycode = lw_company
      IMPORTING
        o_companycode = ls_companycode_info.


**********************************************************************
*    DATA: lt_where_clauses TYPE TABLE OF string.
*    APPEND | postingdate >= @lv_start_date and postingdate <= @lv_end_date| TO lt_where_clauses.
*    APPEND |and financialaccounttype = 'K'| TO lt_where_clauses.
*    APPEND |and supplier IS NOT NULL| TO lt_where_clauses.
*    APPEND |and debitcreditcode IN ('S', 'H')| TO lt_where_clauses.
*    APPEND |and LEDGER = '0L'| TO lt_where_clauses.
**    APPEND |and TRANSACTIONCURRENCY = @lv_currency| TO lt_where_clauses.
*
*    IF lv_compcode_prov = abap_true.
*      APPEND |and companycode IN @lr_companycode| TO lt_where_clauses.
*    ENDIF.
*    IF lv_partner_prov = abap_true.
*      APPEND |and supplier IN @lr_partner| TO lt_where_clauses.
*    ENDIF.
*    IF lv_account_prov = abap_true.
*      APPEND |and glaccount IN @lr_account| TO lt_where_clauses.
*    ENDIF.
*    READ TABLE lr_currency INTO DATA(ls_currency) INDEX 1.
*    IF lv_currency_prov = abap_true AND ls_currency-low NE 'VND'.
*      APPEND |AND transactioncurrency IN @lr_currency| TO lt_where_clauses.
*    ENDIF.
*
*
*    " 2. Aggregate supplier data from I_JournalEntryItem
*    " select total debit and credit amounts for each supplier, company code, currency, and GL account in period
*    SELECT companycode AS rbukrs,
*           supplier AS bp,
*           transactioncurrency,
*           glaccount AS accountnumber,
*           companycodecurrency,
*           SUM( CASE WHEN debitcreditcode = 'S' THEN amountincompanycodecurrency ELSE 0 END ) AS total_debit,
*           SUM( CASE WHEN debitcreditcode = 'H' THEN amountincompanycodecurrency ELSE 0 END ) AS total_credit,
*           SUM( CASE WHEN debitcreditcode = 'S' THEN amountintransactioncurrency ELSE 0 END ) AS total_debit_tran,
*           SUM( CASE WHEN debitcreditcode = 'H' THEN amountintransactioncurrency ELSE 0 END ) AS total_credit_tran
*      FROM i_journalentryitem
*      WHERE (lt_where_clauses)
*      GROUP BY companycode, supplier, companycodecurrency, glaccount, transactioncurrency
*      INTO TABLE @DATA(lt_items).
*    SORT lt_items BY bp.

********************************************************************** Lay chi tiet de bo chung tu clear
    READ TABLE lr_currency INTO DATA(ls_currency) INDEX 1.
    DATA : lt_items TYPE TABLE OF zst_item,
           ls_items TYPE zst_item.
    DATA: lt_where_clauses TYPE TABLE OF string.
    APPEND | postingdate >= @lv_start_date AND postingdate <= @lv_end_date| TO lt_where_clauses.
    APPEND |AND financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |AND supplier IS NOT NULL| TO lt_where_clauses.
    APPEND |AND debitcreditcode IN ('S', 'H')| TO lt_where_clauses.
    APPEND |AND ledger = '0L'| TO lt_where_clauses.

    IF lv_compcode_prov = abap_true.
      APPEND |AND companycode IN @lr_companycode| TO lt_where_clauses.
    ENDIF.
    IF lv_partner_prov = abap_true.
      APPEND |AND supplier IN @lr_partner| TO lt_where_clauses.
    ENDIF.
    IF lv_account_prov = abap_true.
      APPEND |AND glaccount IN @lr_account| TO lt_where_clauses.
    ENDIF.

    READ TABLE lr_currency INTO DATA(ls_curr) INDEX 1.

    IF lv_currency_prov = abap_true AND ls_curr-low NE 'VND'.
      APPEND |AND transactioncurrency IN @lr_currency| TO lt_where_clauses.
    ENDIF.

    SELECT companycode AS rbukrs,
           supplier AS bp,
           transactioncurrency AS rhcur,
           glaccount AS accountnumber,
           fiscalyear,
           accountingdocument,
           isreversed,
           reversalreferencedocument,
           reversalreferencedocumentcntxt,
           debitcreditcode,
           amountincompanycodecurrency,
           amountintransactioncurrency,
           transactioncurrency,
           companycodecurrency,
           clearingaccountingdocument
        FROM i_journalentryitem
        WHERE (lt_where_clauses)
        INTO TABLE @DATA(lt_items_temp).
    SORT lt_items_temp BY rbukrs accountnumber fiscalyear ASCENDING.

    IF sy-subrc EQ 0.
      SELECT companycode,
             fiscalyear,
             accountingdocument,
             isreversal,
             isreversed,
             reversedocument,
             originalreferencedocument
          FROM i_journalentry
          FOR ALL ENTRIES IN @lt_items_temp
          WHERE companycode = @lt_items_temp-rbukrs
          AND accountingdocument = @lt_items_temp-accountingdocument
          AND fiscalyear = @lt_items_temp-fiscalyear
          INTO TABLE @DATA(lt_journal_headers).
      SORT lt_journal_headers BY companycode accountingdocument fiscalyear ASCENDING.
    ENDIF.

    " loại bỏ cặp chứng từ hủy cùng kỳ.
    DATA: lt_huy          LIKE lt_items_temp,
          ls_huy          LIKE LINE OF lt_huy,
          lw_thanhtoan_nt TYPE char1,
          lv_index_huy    TYPE sy-tabix,

          lv_length       TYPE n LENGTH 3,
          lv_docnum       TYPE i_journalentryitem-accountingdocument,
          lv_year         TYPE i_journalentryitem-fiscalyear.

    lt_huy = lt_items_temp.


    SORT lt_huy BY rbukrs accountingdocument fiscalyear ASCENDING.

    LOOP AT lt_huy INTO DATA(ls_check_item) WHERE isreversed IS NOT INITIAL.
      lv_index_huy = sy-tabix.

      READ TABLE lt_journal_headers INTO DATA(ls_check_header) WITH KEY companycode = ls_check_item-rbukrs
                                                                        accountingdocument = ls_check_item-accountingdocument
                                                                        fiscalyear = ls_check_item-fiscalyear BINARY SEARCH.

      IF sy-subrc = 0.
        lv_length = strlen( ls_check_header-originalreferencedocument ) - 4.
        lv_docnum = ls_check_header-originalreferencedocument(lv_length).
        lv_year = ls_check_header-originalreferencedocument+lv_length.

        IF lv_docnum IS NOT INITIAL.
          DELETE lt_items_temp WHERE reversalreferencedocument = lv_docnum AND fiscalyear = lv_year.
          IF sy-subrc = 0.
            DELETE lt_items_temp WHERE accountingdocument = ls_check_item-accountingdocument AND fiscalyear = lv_year.
          ENDIF.
        ENDIF.
      ENDIF.

      CLEAR: ls_check_item, ls_check_header, lv_length, lv_docnum, lv_year.
    ENDLOOP.

    FREE: lt_items.
    " Bo chung tu clear :
    " Xóa bỏ chứng từ case clear.
    DATA(lt_journal_items_tmp) = lt_items_temp.
    sort lt_items_temp by accountingdocument bp amountincompanycodecurrency amountintransactioncurrency.
    SORT lt_journal_items_tmp BY accountingdocument accountnumber amountincompanycodecurrency debitcreditcode amountintransactioncurrency bp.
    LOOP AT lt_journal_items_tmp INTO DATA(ls_line_clear).
      ls_line_clear-amountincompanycodecurrency = ls_line_clear-amountincompanycodecurrency * -1.
      ls_line_clear-amountintransactioncurrency = ls_line_clear-amountintransactioncurrency * -1.
      IF ls_line_clear-amountincompanycodecurrency IS NOT INITIAL AND ls_line_clear-debitcreditcode = 'S'.
        READ TABLE lt_journal_items_tmp INTO DATA(ls_line_items_tmp) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                              accountnumber = ls_line_clear-accountnumber
                                                                              amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                              debitcreditcode = 'H'
                                                                              amountintransactioncurrency = ls_line_clear-amountintransactioncurrency
                                                                              bp = ls_line_clear-bp BINARY SEARCH.
        IF sy-subrc = 0.
          READ TABLE lt_items_temp INTO DATA(ls_clear_h) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                  bp = ls_line_clear-bp
                                                                  amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                  amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency BINARY SEARCH.
          IF sy-subrc = 0.
*          DELETE lt_items_temp WHERE accountingdocument = ls_line_clear-accountingdocument
*                                 AND bp = ls_line_clear-bp
*                                 AND amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
*                                 AND amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.
            DELETE lt_items_temp INDEX sy-tabix.
          ENDIF.
        ENDIF.

      ELSEIF ls_line_clear-amountincompanycodecurrency IS NOT INITIAL AND ls_line_clear-debitcreditcode = 'H'.
        READ TABLE lt_journal_items_tmp INTO DATA(ls_line_clear_tmp) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                              accountnumber = ls_line_clear-accountnumber
                                                                              amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                              debitcreditcode = 'S'
                                                                              amountintransactioncurrency = ls_line_clear-amountintransactioncurrency
                                                                              bp = ls_line_clear-bp BINARY SEARCH.
        IF sy-subrc = 0.
          READ TABLE lt_items_temp INTO DATA(ls_clear_s) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                   bp = ls_line_clear-bp
                                                                   amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                   amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency BINARY SEARCH.
          IF sy-subrc = 0.
*          DELETE lt_items_temp WHERE accountingdocument = ls_line_clear-accountingdocument
*                                 AND bp = ls_line_clear-bp
*                                 AND amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
*                                 AND amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.
            DELETE lt_items_temp INDEX sy-tabix.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
    "
    LOOP AT lt_items_temp INTO DATA(lg_journal_items)
    GROUP BY (
        companycode = lg_journal_items-rbukrs
        glaccount = lg_journal_items-accountnumber
        supplier =  lg_journal_items-bp
        companycodecurrency = lg_journal_items-companycodecurrency
        transactioncurrency = lg_journal_items-rhcur
    ) ASSIGNING FIELD-SYMBOL(<group>).
      ls_items-rbukrs = <group>-companycode.
      ls_items-bp = <group>-supplier.
      ls_items-accountnumber = <group>-glaccount.
      ls_items-companycodecurrency = <group>-companycodecurrency .
      ls_items-rhcur = <group>-transactioncurrency.

      LOOP AT lt_items_temp INTO DATA(ls_items_temp) WHERE rbukrs = <group>-companycode
                                                     AND accountnumber = <group>-glaccount
                                                     AND bp = <group>-supplier
                                                     AND companycodecurrency = <group>-companycodecurrency
                                                     AND transactioncurrency = <group>-transactioncurrency.
        CLEAR : lw_thanhtoan_nt.
        IF ls_items_temp-debitcreditcode = 'S'.
          ls_items-total_debit = ls_items-total_debit + ls_items_temp-amountincompanycodecurrency.
          ls_items-total_debit_tran = ls_items-total_debit_tran + ls_items_temp-amountintransactioncurrency.
        ELSEIF ls_items_temp-debitcreditcode = 'H'.
          ls_items-total_credit = ls_items-total_credit + ls_items_temp-amountincompanycodecurrency.
          ls_items-total_credit_tran = ls_items-total_credit_tran + ls_items_temp-amountintransactioncurrency.
        ENDIF.
        CLEAR: ls_items_temp.
      ENDLOOP.
      APPEND ls_items TO lt_items.
      CLEAR: ls_items, lg_journal_items.
    ENDLOOP.
**********************************************************************

*    CHECK lt_items IS NOT INITIAL.
*    CLEAR: lr_companycode, lr_partner.
*    LOOP AT lt_items INTO DATA(ls_item1).
*      " append company code and supplier to lr_companycode and lr_partner
*      APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_item1-rbukrs ) TO lr_companycode.
*      APPEND VALUE #( sign = 'I' option = 'EQ' low = |{ ls_item1-bp ALPHA = IN WIDTH = 10 }| ) TO lr_partner.
*    ENDLOOP.

    " 3. Fetch open and end balances in bulk
    CLEAR : lt_where_clauses.
    APPEND | postingdate < @lv_start_date| TO lt_where_clauses.
    APPEND |and financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |and supplier IS NOT NULL| TO lt_where_clauses.
    APPEND |and debitcreditcode IN ('S', 'H')| TO lt_where_clauses.
    APPEND |and LEDGER = '0L'| TO lt_where_clauses.
*    APPEND |and TRANSACTIONCURRENCY = @lv_currency| TO lt_where_clauses.

    IF lv_compcode_prov = abap_true.
      APPEND |and companycode IN @lr_companycode| TO lt_where_clauses.
    ENDIF.
    IF lv_partner_prov = abap_true.
      APPEND |and supplier IN @lr_partner| TO lt_where_clauses.
    ENDIF.
    IF lv_account_prov = abap_true.
      APPEND |and glaccount IN @lr_account| TO lt_where_clauses.
    ENDIF.
    IF lv_currency_prov = abap_true AND ls_currency-low NE 'VND'.
      APPEND |AND transactioncurrency IN @lr_currency| TO lt_where_clauses.
    ENDIF.
    "
    SELECT supplier AS bp,
           companycode AS rbukrs,
           transactioncurrency,
           glaccount AS accountnumber,
           companycodecurrency,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountincompanycodecurrency ELSE 0 END ) AS open_debit,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountincompanycodecurrency ELSE 0 END ) AS open_credit,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountintransactioncurrency ELSE 0 END ) AS open_debit_tran,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountintransactioncurrency ELSE 0 END ) AS open_credit_tran
      FROM i_journalentryitem
      WHERE (lt_where_clauses)
      GROUP BY supplier, companycode,companycodecurrency, glaccount, transactioncurrency
      INTO TABLE @DATA(lt_open_balances).
    SORT lt_open_balances BY bp accountnumber transactioncurrency companycodecurrency ASCENDING.
    " 4. Fetch supplier details
    SELECT supplier AS bp,
           suppliername AS bp_name
      FROM i_supplier
      WHERE supplier IN @lr_partner
      INTO TABLE @DATA(lt_suppliers).
    SORT lt_suppliers BY bp.

    SELECT businesspartner AS bp,
           businesspartnercategory AS bp_cat
    FROM i_businesspartner
    WHERE businesspartner IN @lr_partner
    INTO TABLE @DATA(lt_businesspartner).
    SORT lt_businesspartner BY bp.

    SELECT b~businesspartner AS bp,
           b~businesspartnergrouping AS bp_gr,
           t~businesspartnergroupingtext AS bp_gr_title
      FROM i_businesspartner AS b
      LEFT OUTER JOIN i_businesspartnergroupingtext AS t
        ON t~businesspartnergrouping = b~businesspartnergrouping
        AND t~language = @sy-langu
      WHERE b~businesspartner IN @lr_partner
        AND b~businesspartnergrouping IN @lr_bpgroup
      INTO TABLE @DATA(lt_bp_groups).
    SORT lt_bp_groups BY bp.

    " 5. Build result table
    SORT lt_open_balances BY rbukrs bp accountnumber transactioncurrency companycodecurrency.
    LOOP AT lt_items INTO DATA(ls_item).
      DATA(ls_result) = VALUE zc_accpay_summary(
*        companyname = ls_companycode_info-companycodename
*        companyaddr = ls_companycode_info-companycodeaddr
        rbukrs = ls_item-rbukrs
        bp = ls_item-bp
        rhcur = ls_item-rhcur
        companycodecurrency = ls_item-companycodecurrency
*        accountnumber = ls_item-accountnumber
        accountnumber       = |{ ls_item-accountnumber ALPHA = OUT }|
        total_debit = ls_item-total_debit
        total_credit = ls_item-total_credit
        total_debit_tran = ls_item-total_debit_tran
        total_credit_tran = ls_item-total_credit_tran
        p_start_date = lv_start_date
        p_end_date = lv_end_date
      ).
      " Assign open balances
      READ TABLE lt_open_balances INTO DATA(ls_open) WITH KEY rbukrs = ls_item-rbukrs
                                                               bp = ls_item-bp
                                                               accountnumber = ls_item-accountnumber
                                                               transactioncurrency = ls_item-rhcur
                                                               companycodecurrency = ls_item-companycodecurrency
                                                               BINARY SEARCH.
      IF sy-subrc = 0.
        DATA(lv_index_del) = sy-tabix.
        ls_result-open_debit = ls_open-open_debit.
        ls_result-open_credit = ls_open-open_credit.
        ls_result-open_debit_tran = ls_open-open_debit_tran.
        ls_result-open_credit_tran = ls_open-open_credit_tran.
        DELETE lt_open_balances INDEX lv_index_del.
      ENDIF.

      " Assign end balances
*      READ TABLE lt_end_balances INTO DATA(ls_end) WITH KEY bp = ls_item-bp rbukrs = ls_item-rbukrs BINARY SEARCH.
*      IF sy-subrc = 0.
*        ls_result-end_debit = ls_end-end_debit.
*        ls_result-end_credit = ls_end-end_credit.
*      ENDIF.


      " Assign supplier name

      zcl_jp_common_core=>get_bp_info_new(
       EXPORTING
           i_businesspartner = ls_item-bp
       IMPORTING
       o_bp_info = DATA(ls_supplier)

).
*      READ TABLE lt_suppliers INTO DATA(ls_supplier) WITH KEY bp = ls_item-bp BINARY SEARCH.
*      IF sy-subrc = 0.
      READ TABLE lt_businesspartner INTO DATA(ls_businesspartner) WITH KEY bp = ls_item-bp.
      IF ls_businesspartner-bp_cat = '2'.
        ls_result-bp_name = ls_supplier-bpname.
      ELSE.
        READ TABLE lt_suppliers INTO DATA(ls_supplier_person) WITH KEY bp = ls_item-bp BINARY SEARCH.
        IF sy-subrc = 0.
          ls_result-bp_name = ls_supplier_person-bp_name.
        ENDIF.
      ENDIF.
      " Assign business partner group and title
      READ TABLE lt_bp_groups INTO DATA(ls_bp_group) WITH KEY bp = ls_item-bp BINARY SEARCH.
      IF sy-subrc = 0.
        ls_result-bp_gr = ls_bp_group-bp_gr.
        ls_result-bp_gr_title = ls_bp_group-bp_gr_title.
      ENDIF.

      APPEND ls_result TO lt_result.
      CLEAR ls_result.
    ENDLOOP.
**********************************************************************
* Them case BP không phát sinh, vẫn cho lên báo cáo
    LOOP AT lt_open_balances INTO DATA(ls_open_balances).
      DATA(ls_result_kps) = VALUE zc_accpay_summary(
*        companyname = ls_companycode_info-companycodename
*        companyaddr = ls_companycode_info-companycodeaddr
       rbukrs = ls_open_balances-rbukrs
       bp = ls_open_balances-bp
       rhcur = ls_open_balances-transactioncurrency
       companycodecurrency = ls_open_balances-companycodecurrency
*        accountnumber = ls_item-accountnumber
       accountnumber       = |{ ls_open_balances-accountnumber ALPHA = OUT }|
*       total_debit = ls_open_balances-open_debit
*       total_credit = ls_open_balances-open_credit
*        total_debit_tran = ls_item-total_debit_tran
*        total_credit_tran = ls_item-total_credit_tran
       p_start_date = lv_start_date
       p_end_date = lv_end_date
     ).
      ls_result_kps-open_debit = ls_open_balances-open_debit.
      ls_result_kps-open_credit = ls_open_balances-open_credit.
      ls_result_kps-end_debit = ls_open_balances-open_debit.
      ls_result_kps-end_credit = ls_open_balances-open_credit.
      ls_result_kps-open_debit_tran = ls_open_balances-open_debit_tran.
      ls_result_kps-open_credit_tran = ls_open_balances-open_credit_tran.
      ls_result_kps-end_debit_tran = ls_open_balances-open_debit_tran.
      ls_result_kps-end_credit_tran = ls_open_balances-open_credit_tran.
      zcl_jp_common_core=>get_bp_info_new(
    EXPORTING
        i_businesspartner = ls_open_balances-bp
    IMPORTING
    o_bp_info = ls_supplier

).
*      READ TABLE lt_suppliers INTO DATA(ls_supplier) WITH KEY bp = ls_item-bp BINARY SEARCH.
*      IF sy-subrc = 0.
      READ TABLE lt_businesspartner INTO ls_businesspartner WITH KEY bp = ls_open_balances-bp.
      IF ls_businesspartner-bp_cat = '2'.
        ls_result_kps-bp_name = ls_supplier-bpname.
      ELSE.
        READ TABLE lt_suppliers INTO ls_supplier_person WITH KEY bp = ls_open_balances-bp BINARY SEARCH.
        IF sy-subrc = 0.
          ls_result_kps-bp_name = ls_supplier_person-bp_name.
        ENDIF.
      ENDIF.
      " Assign business partner group and title
      READ TABLE lt_bp_groups INTO ls_bp_group WITH KEY bp = ls_open_balances-bp BINARY SEARCH.
      IF sy-subrc = 0.
        ls_result_kps-bp_gr = ls_bp_group-bp_gr.
        ls_result_kps-bp_gr_title = ls_bp_group-bp_gr_title.
      ENDIF.

      APPEND ls_result_kps TO lt_result.
      CLEAR ls_result_kps.
    ENDLOOP.

    " Remove amount if tran currency = 'VND'
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<fs_final>).
      IF <fs_final>-rhcur = 'VND' OR ls_currency-low = 'VND' OR ( ls_currency-low = '' AND <fs_final>-rhcur NE 'USD' ).
        CLEAR:
        <fs_final>-open_credit_tran,
        <fs_final>-open_debit_tran,
        <fs_final>-end_credit_tran,
        <fs_final>-end_debit_tran,
        <fs_final>-total_credit_tran,
        <fs_final>-total_debit_tran.
      ENDIF.
    ENDLOOP.
**********************************************************************
    IF lv_bpgroup_prov = abap_true.
      DELETE lt_result WHERE bp_gr IS INITIAL.
    ENDIF.
    DELETE lt_result WHERE open_credit = 0 AND open_debit = 0 AND end_credit = 0 AND end_debit = 0 AND total_credit = 0 AND total_debit = 0
    AND open_credit_tran = 0 AND open_debit_tran = 0 AND end_credit_tran = 0 AND end_debit_tran = 0 AND total_credit_tran = 0 AND total_debit_tran = 0.
    DATA: lv_open_amount TYPE zc_accpay_summary-open_debit,
          lv_end_amount  TYPE zc_accpay_summary-end_debit.
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<fs_result>).
      lv_open_amount = <fs_result>-open_credit + <fs_result>-open_debit.
      IF lv_open_amount >= 0.
        CLEAR <fs_result>-open_credit.
        <fs_result>-open_debit = lv_open_amount.
      ELSE.
        CLEAR <fs_result>-open_debit.
        <fs_result>-open_credit = lv_open_amount.
      ENDIF.
      CLEAR lv_open_amount.
      lv_end_amount = <fs_result>-open_credit + <fs_result>-open_debit
                      + <fs_result>-total_credit + <fs_result>-total_debit.
      IF lv_end_amount >= 0.
        CLEAR <fs_result>-end_credit.
        <fs_result>-end_debit = lv_end_amount.
      ELSE.
        CLEAR <fs_result>-end_debit.
        <fs_result>-end_credit = lv_end_amount.
      ENDIF.
      CLEAR lv_end_amount.
      " transaction currency amounts
      lv_open_amount = <fs_result>-open_credit_tran + <fs_result>-open_debit_tran.
      IF lv_open_amount >= 0.
        CLEAR <fs_result>-open_credit_tran.
        <fs_result>-open_debit_tran = lv_open_amount.
      ELSE.
        CLEAR <fs_result>-open_debit_tran.
        <fs_result>-open_credit_tran = lv_open_amount.
      ENDIF.
      CLEAR lv_open_amount.
      lv_end_amount = <fs_result>-open_credit_tran + <fs_result>-open_debit_tran
                      + <fs_result>-total_credit_tran + <fs_result>-total_debit_tran.
      IF lv_end_amount >= 0.
        CLEAR <fs_result>-end_credit_tran.
        <fs_result>-end_debit_tran = lv_end_amount.
      ELSE.
        CLEAR <fs_result>-end_debit_tran.
        <fs_result>-end_credit_tran = lv_end_amount.
      ENDIF.
      CLEAR lv_end_amount.
    ENDLOOP.
**********************************************************************
    " 5. Change sign for all balance amounts
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<lfs_temp>).
      <lfs_temp>-open_credit = abs( <lfs_temp>-open_credit ).
      <lfs_temp>-total_credit = <lfs_temp>-total_credit * -1.
      <lfs_temp>-end_credit = abs( <lfs_temp>-end_credit ).
      " Transaction currency amounts
      <lfs_temp>-open_credit_tran = abs( <lfs_temp>-open_credit_tran ).
      <lfs_temp>-total_credit_tran = <lfs_temp>-total_credit_tran * -1.
      <lfs_temp>-end_credit_tran = abs( <lfs_temp>-end_credit_tran ).
    ENDLOOP.
********************************************************************
    DATA: lt_result_temp LIKE lt_result,
          ls_result_temp LIKE LINE OF lt_result_temp.

    LOOP AT lt_result INTO DATA(lg_result_gom)
    GROUP BY (
        companycode = lg_result_gom-rbukrs
        glaccount = lg_result_gom-accountnumber
        customer =  lg_result_gom-bp
        companycodecurrency = lg_result_gom-companycodecurrency
    ) ASSIGNING FIELD-SYMBOL(<group_gom>).
      ls_result_temp-rbukrs = <group_gom>-companycode.
      ls_result_temp-bp = <group_gom>-customer.
      ls_result_temp-accountnumber = <group_gom>-glaccount.
      ls_result_temp-companycodecurrency = <group_gom>-companycodecurrency .
*      ls_result_temp-rhcur = <group_gom>-transactioncurrency.

      LOOP AT lt_result INTO ls_result WHERE rbukrs = <group_gom>-companycode
                                       AND bp = <group_gom>-customer
                                       AND accountnumber = <group_gom>-glaccount.

        ls_result_temp-bp_gr = ls_result-bp_gr.
*        ls_result_temp-companyname = ls_result-companyname.
*        ls_result_temp-companyaddr = ls_result-companyaddr.

        IF ls_result_temp-rhcur IS INITIAL AND ls_result-rhcur NE 'VND'.
          ls_result_temp-rhcur = ls_result-rhcur.
        ENDIF.

        ls_result_temp-bp_gr_title = ls_result-bp_gr_title.
        ls_result_temp-bp_name = ls_result-bp_name.

        ls_result_temp-open_debit = ls_result_temp-open_debit + ls_result-open_debit.
        ls_result_temp-open_debit_tran = ls_result_temp-open_debit_tran + ls_result-open_debit_tran.
        ls_result_temp-open_credit = ls_result_temp-open_credit + ls_result-open_credit.
        ls_result_temp-open_credit_tran = ls_result_temp-open_credit_tran + ls_result-open_credit_tran.

        ls_result_temp-total_debit = ls_result_temp-total_debit + ls_result-total_debit.
        ls_result_temp-total_debit_tran = ls_result_temp-total_debit_tran + ls_result-total_debit_tran.
        ls_result_temp-total_credit = ls_result_temp-total_credit + ls_result-total_credit.
        ls_result_temp-total_credit_tran = ls_result_temp-total_credit_tran + ls_result-total_credit_tran.

        ls_result_temp-end_debit = ls_result_temp-end_debit + ls_result-end_debit.
        ls_result_temp-end_debit_tran = ls_result_temp-end_debit_tran + ls_result-end_debit_tran.
        ls_result_temp-end_credit = ls_result_temp-end_credit + ls_result-end_credit.
        ls_result_temp-end_credit_tran = ls_result_temp-end_credit_tran + ls_result-end_credit_tran.

        ls_result_temp-p_start_date = ls_result-p_start_date.
        ls_result_temp-p_end_date = ls_result-p_end_date.

        CLEAR ls_result.
      ENDLOOP.

      DATA lv_chenh_lech TYPE zc_accpay_summary-open_credit.
      DATA lv_chenh_lech_total TYPE zc_accpay_summary-open_credit.

      " tính dư đầu kỳ theo company code thêm chênh lệch
      IF ( ls_result_temp-open_credit - ls_result_temp-open_debit - lv_chenh_lech ) > 0.
        ls_result_temp-open_credit = ls_result_temp-open_credit - ls_result_temp-open_debit - lv_chenh_lech.
        ls_result_temp-open_debit = 0.
      ELSEIF ( ls_result_temp-open_credit - ls_result_temp-open_debit - lv_chenh_lech ) < 0.
        ls_result_temp-open_debit = abs( ls_result_temp-open_credit - ls_result_temp-open_debit - lv_chenh_lech ).
        ls_result_temp-open_credit = 0.
      ELSEIF ( ls_result_temp-open_credit - ls_result_temp-open_debit - lv_chenh_lech ) = 0.
        ls_result_temp-open_debit = 0.
        ls_result_temp-open_credit = 0.
      ENDIF.

      " tính dư đầu kỳ theo transaction currency thêm chênh lệch
      IF ( ls_result_temp-open_credit_tran - ls_result_temp-open_debit_tran ) > 0.
        ls_result_temp-open_credit_tran = ls_result_temp-open_credit_tran - ls_result_temp-open_debit_tran.
        ls_result_temp-open_debit_tran = 0.
      ELSEIF ( ls_result_temp-open_credit_tran - ls_result_temp-open_debit_tran ) < 0.
        ls_result_temp-open_debit_tran = abs( ls_result_temp-open_credit_tran - ls_result_temp-open_debit_tran ).
        ls_result_temp-open_credit_tran = 0.
      ELSEIF ( ls_result_temp-open_credit_tran - ls_result_temp-open_debit_tran ) = 0.
        ls_result_temp-open_debit_tran = 0.
        ls_result_temp-open_credit_tran = 0.
      ENDIF.

      " tính tổng phát sinh trong kỳ thêm chênh lệch
      ls_result_temp-total_debit = abs( ls_result_temp-total_debit ).
      ls_result_temp-total_credit = abs( ls_result_temp-total_credit ).

      " tính cuối kỳ theo company currency thêm chênh lệch
      IF ( ls_result_temp-end_credit - ls_result_temp-end_debit - lv_chenh_lech - lv_chenh_lech_total ) > 0.
        ls_result_temp-end_credit = ls_result_temp-end_credit - ls_result_temp-end_debit - lv_chenh_lech - lv_chenh_lech_total.
        ls_result_temp-end_debit = 0.
      ELSEIF ( ls_result_temp-end_credit - ls_result_temp-end_debit - lv_chenh_lech - lv_chenh_lech_total ) < 0.
        ls_result_temp-end_debit = abs( ls_result_temp-end_credit - ls_result_temp-end_debit - lv_chenh_lech - lv_chenh_lech_total ).
        ls_result_temp-end_credit = 0.
      ELSEIF ( ls_result_temp-end_credit - ls_result_temp-end_debit - lv_chenh_lech - lv_chenh_lech_total ) = 0.
        ls_result_temp-end_debit = 0.
        ls_result_temp-end_credit = 0.
      ENDIF.

      " tính cuối kỳ theo transaction currency thêm chênh lệch
      IF ( ls_result_temp-end_credit_tran - ls_result_temp-end_debit_tran ) > 0.
        ls_result_temp-end_credit_tran = ls_result_temp-end_credit_tran - ls_result_temp-end_debit_tran.
        ls_result_temp-end_debit_tran = 0.
      ELSEIF ( ls_result_temp-end_credit_tran - ls_result_temp-end_debit_tran ) < 0.
        ls_result_temp-end_debit_tran = abs( ls_result_temp-end_credit_tran - ls_result_temp-end_debit_tran ).
        ls_result_temp-end_credit_tran = 0.
      ELSEIF ( ls_result_temp-end_credit_tran - ls_result_temp-end_debit_tran ) = 0.
        ls_result_temp-end_debit_tran = 0.
        ls_result_temp-end_credit_tran = 0.
      ENDIF.

      IF ls_result_temp-rhcur IS INITIAL.
        ls_result_temp-rhcur = 'VND'.
      ENDIF.

      APPEND ls_result_temp TO lt_result_temp.
      CLEAR: ls_result_temp.
    ENDLOOP.

    lt_result = CORRESPONDING #( lt_result_temp ).
**********************************************************************
    SORT lt_result BY bp ASCENDING.
    " 6. Apply sorting
    DATA(sort_order) = VALUE abap_sortorder_tab(
      FOR sort_element IN io_request->get_sort_elements( )
      ( name = sort_element-element_name descending = sort_element-descending ) ).
    IF sort_order IS NOT INITIAL.
      SORT lt_result BY (sort_order).
    ENDIF.
**********************************************************************
    DATA: ls_page_info      TYPE zcl_get_filter_ar_sum=>ty_page_info.
    DATA(lo_common_app) = zcl_get_filter_ar_sum=>get_instance( ).

    "  LẤY FILTER TỪ UI (CompanyCode, PostingDate, ...)
*        zcl_get_filter_bangkevat=>get_instance( )->get_fillter_app(
    lo_common_app->get_fillter_app(
      EXPORTING
        io_request   = io_request
        io_response  = io_response
      IMPORTING
        wa_page_info     = ls_page_info
    ).
    " 7. Apply paging
    DATA(max_rows) = COND #( WHEN ls_page_info-page_size = if_rap_query_paging=>page_size_unlimited THEN 0
           ELSE ls_page_info-page_size ).

    max_rows = ls_page_info-page_size + ls_page_info-offset.

    LOOP AT lt_result INTO ls_result.
      IF sy-tabix > ls_page_info-offset.
        IF sy-tabix > max_rows.
          EXIT.
        ELSE.
          APPEND ls_result TO lt_result1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( lt_result ) ).
    ENDIF.

    IF io_request->is_data_requested( ).
      io_response->set_data( lt_result1 ).
    ENDIF.
    " 7. Apply paging
*    DATA(lv_total_records) = lines( lt_result ).
*
*    DATA(lo_paging) = io_request->get_paging( ).
*    IF lo_paging IS BOUND.
*      DATA(top) = lo_paging->get_page_size( ).
*      IF top < 0. " -1 means all records
*        top = lv_total_records.
*      ENDIF.
*      DATA(skip) = lo_paging->get_offset( ).
*
*      IF skip >= lv_total_records.
*        CLEAR lt_result. " Offset is beyond the total number of records
*      ELSEIF top = 0.
*        CLEAR lt_result. " No records requested
*      ELSE.
*        " Calculate the actual range to keep
*        DATA(lv_start_index) = skip + 1. " ABAP uses 1-based indexing
*        DATA(lv_end_index) = skip + top.
*
*        " Ensure end index doesn't exceed table size
*        IF lv_end_index > lv_total_records.
*          lv_end_index = lv_total_records.
*        ENDIF.
*
*        " Create a new table with only the required records
*        DATA: lt_paged_result LIKE lt_result.
*        CLEAR lt_paged_result.
*
*        " Copy only the required records
*        DATA(lv_index) = lv_start_index.
*        WHILE lv_index <= lv_end_index.
*          APPEND lt_result[ lv_index ] TO lt_paged_result.
*          lv_index = lv_index + 1.
*        ENDWHILE.
*
*        lt_result = lt_paged_result.
*      ENDIF.
*    ENDIF.
*    " 6. Set response
*    IF io_request->is_data_requested( ).
*      io_response->set_data( lt_result ).
*    ENDIF.
*    IF io_request->is_total_numb_of_rec_requested( ).
*      io_response->set_total_number_of_records( lines( lt_result ) ).
*    ENDIF.
  ENDMETHOD.
ENDCLASS.
