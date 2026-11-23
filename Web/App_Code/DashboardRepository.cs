using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;

/// <summary>
/// Data access for the chick sales &amp; payment dashboard.
/// All SQL lives in stored procedures (Database/01_Dashboard_Objects.sql).
/// </summary>
public static class DashboardRepository
{
    private const int CommandTimeoutSeconds = 90;

    internal static string ConnectionString
    {
        get { return ConfigurationManager.ConnectionStrings["ChickDB"].ConnectionString; }
    }

    /// <summary>Sessions, areas of the selected (or latest) session.</summary>
    public static Dictionary<string, object> GetFilters(string session)
    {
        using (var cn = new SqlConnection(ConnectionString))
        using (var cmd = new SqlCommand("dbo.usp_ChickDash_Filters", cn))
        {
            cmd.CommandType = CommandType.StoredProcedure;
            cmd.CommandTimeout = CommandTimeoutSeconds;
            AddVarChar(cmd, "@Session", 50, session);

            cn.Open();
            using (var rd = cmd.ExecuteReader())
            {
                var sessions = new List<string>();
                while (rd.Read())
                    sessions.Add(Convert.ToString(rd["Session"]));

                rd.NextResult();
                var areas = ReadRows(rd);

                rd.NextResult();
                string current = null;
                if (rd.Read() && rd["CurrentSession"] != DBNull.Value)
                    current = Convert.ToString(rd["CurrentSession"]);

                return new Dictionary<string, object>
                {
                    { "sessions", sessions },
                    { "areas", areas },
                    { "currentSession", current }
                };
            }
        }
    }

    /// <summary>All dashboard data for one filter combination (9 result sets, one round trip).</summary>
    public static Dictionary<string, object> GetDashboard(string session, string areaCode, string chickType,
                                                          DateTime? fromDate, DateTime? toDate)
    {
        using (var cn = new SqlConnection(ConnectionString))
        using (var cmd = new SqlCommand("dbo.usp_ChickDash_Data", cn))
        {
            cmd.CommandType = CommandType.StoredProcedure;
            cmd.CommandTimeout = CommandTimeoutSeconds;
            AddVarChar(cmd, "@Session", 50, session);
            AddVarChar(cmd, "@AreaCode", 50, areaCode);
            AddVarChar(cmd, "@ChickType", 20, chickType);
            cmd.Parameters.Add("@FromDate", SqlDbType.Date).Value = (object)fromDate ?? DBNull.Value;
            cmd.Parameters.Add("@ToDate", SqlDbType.Date).Value = (object)toDate ?? DBNull.Value;

            var result = new Dictionary<string, object>();
            string[] names = { "kpi", "byType", "monthly", "payMode", "payType", "areas", "customers", "receipts", "dms" };

            cn.Open();
            using (var rd = cmd.ExecuteReader())
            {
                int i = 0;
                do
                {
                    if (i >= names.Length) break;
                    result[names[i]] = ReadRows(rd);
                    i++;
                } while (rd.NextResult());
            }

            // KPI is a single row - flatten it
            var kpiRows = result.ContainsKey("kpi") ? (List<Dictionary<string, object>>)result["kpi"] : null;
            result["kpi"] = (kpiRows != null && kpiRows.Count > 0) ? kpiRows[0] : new Dictionary<string, object>();
            return result;
        }
    }

    // ------------------------------------------------------------------ helpers

    internal static void AddVarChar(SqlCommand cmd, string name, int size, string value)
    {
        value = string.IsNullOrWhiteSpace(value) ? null : value.Trim();
        cmd.Parameters.Add(name, SqlDbType.VarChar, size).Value = (object)value ?? DBNull.Value;
    }

    /// <summary>Reads the current result set into JSON-friendly rows (dates as yyyy-MM-dd, decimals rounded).</summary>
    internal static List<Dictionary<string, object>> ReadRows(SqlDataReader rd)
    {
        var rows = new List<Dictionary<string, object>>();
        int count = rd.FieldCount;
        var columns = new string[count];
        for (int i = 0; i < count; i++) columns[i] = rd.GetName(i);

        while (rd.Read())
        {
            var row = new Dictionary<string, object>(count, StringComparer.Ordinal);
            for (int i = 0; i < count; i++)
            {
                object v = rd.GetValue(i);
                if (v == DBNull.Value) v = null;
                else if (v is DateTime) v = ((DateTime)v).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                else if (v is decimal) v = Math.Round((decimal)v, 2);
                else if (v is string) v = ((string)v).Trim();
                row[columns[i]] = v;
            }
            rows.Add(row);
        }
        return rows;
    }
}
