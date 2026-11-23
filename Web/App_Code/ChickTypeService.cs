using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;

/// <summary>
/// Chick type-wise outstanding and last hatch date (ChickTypes.aspx).
/// Source: PrintData (chick bills) + VENTRY ledger, see Database/08_Chick_Type_Outstanding.sql
/// </summary>
public static class ChickTypeService
{
    public static object GetFilters()
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = Proc(cn, "dbo.usp_ChickType_Filters"))
            {
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var stations = new List<string>();
                    while (rd.Read()) stations.Add(Convert.ToString(rd["Station"]));
                    rd.NextResult();
                    var info = DashboardRepository.ReadRows(rd);
                    var i = info.Count > 0 ? info[0] : new Dictionary<string, object>();
                    return new
                    {
                        ok = true,
                        data = new Dictionary<string, object>
                        {
                            { "stations", stations },
                            { "today", i.ContainsKey("Today") ? i["Today"] : null },
                            { "ledgerFrom", i.ContainsKey("LedgerFrom") ? i["LedgerFrom"] : null },
                            { "ledgerTo", i.ContainsKey("LedgerTo") ? i["LedgerTo"] : null }
                        }
                    };
                }
            }
        }
        catch (Exception ex) { return Fail("GetFilters", ex, "Could not load filters. Please check the database connection."); }
    }

    public static object GetSummary(string station, string asOf)
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = Proc(cn, "dbo.usp_ChickType_Summary"))
            {
                DashboardRepository.AddVarChar(cmd, "@Station", 50, station);
                cmd.Parameters.Add("@AsOf", SqlDbType.Date).Value = Date(asOf);
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var types = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var customers = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var notes = DashboardRepository.ReadRows(rd);
                    return new
                    {
                        ok = true,
                        data = new Dictionary<string, object>
                        {
                            { "types", types }, { "customers", customers },
                            { "notes", notes.Count > 0 ? notes[0] : new Dictionary<string, object>() },
                            { "generatedAt", DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss", CultureInfo.InvariantCulture) }
                        }
                    };
                }
            }
        }
        catch (Exception ex) { return Fail("GetSummary", ex, "Could not load chick type-wise outstanding. Please try again."); }
    }

    public static object GetCustomer(string custKey, string asOf)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(custKey)) return new { ok = false, error = "Customer not specified." };
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = Proc(cn, "dbo.usp_ChickType_Customer"))
            {
                DashboardRepository.AddVarChar(cmd, "@AccCode", 18, custKey.Trim().Length > 18 ? custKey.Trim().Substring(0, 18) : custKey.Trim());
                cmd.Parameters.Add("@AsOf", SqlDbType.Date).Value = Date(asOf);
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var bills = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var credits = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var bal = DashboardRepository.ReadRows(rd);
                    return new
                    {
                        ok = true,
                        data = new Dictionary<string, object>
                        {
                            { "bills", bills }, { "credits", credits },
                            { "balance", bal.Count > 0 ? bal[0] : new Dictionary<string, object>() }
                        }
                    };
                }
            }
        }
        catch (Exception ex) { return Fail("GetCustomer", ex, "Could not load the customer. Please try again."); }
    }

    private static SqlCommand Proc(SqlConnection cn, string name)
    {
        return new SqlCommand(name, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 };
    }

    private static object Date(string s)
    {
        DateTime d;
        return !string.IsNullOrWhiteSpace(s) && DateTime.TryParseExact(s.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d)
            ? (object)d : DBNull.Value;
    }

    private static object Fail(string where, Exception ex, string message)
    {
        System.Diagnostics.Trace.TraceError("ChickTypes." + where + " failed: " + ex);
        return new { ok = false, error = message };
    }
}
